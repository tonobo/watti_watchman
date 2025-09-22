RSpec.describe WattiWatchman::Service::HassFeeder do
  let(:mqtt_params) do
    { host: 'mqtt.klaut.io', port: 1883 }
  end
  let(:update_interval) { 5 }

  subject(:feeder) { described_class.new(mqtt_params: mqtt_params, update_interval: update_interval) }

  describe '#initialize' do
    context 'with valid parameters' do
      it 'does not raise an error' do
        expect {
          described_class.new(mqtt_params: mqtt_params, update_interval: update_interval)
        }.not_to raise_error
      end
    end

    context 'when mqtt_params is not a Hash' do
      it 'raises an ArgumentError' do
        expect {
          described_class.new(mqtt_params: 'wrong-type', update_interval: update_interval)
        }.to raise_error(ArgumentError, /mqtt_params should be a hash/)
      end
    end

    context 'when update_interval is not numeric' do
      it 'raises an ArgumentError' do
        expect {
          described_class.new(mqtt_params: mqtt_params, update_interval: 'nope')
        }.to raise_error(ArgumentError, /update_interval should be a Numeric/)
      end
    end
  end

  describe '#call' do
    let(:mock_mqtt_client) { instance_double(MQTT::Client) }

    let(:metric_definition) do
      double(
        'MetricDefinition',
        hass_klass: 'power',
        metric_id: 'ac_in_power',
        unit: 'W',
        type: 'measurement'
      )
    end

    let(:metric) do
      double(
        'Metric',
        definition: metric_definition,
        value: 123.456,
        _labels: { name: 'test-meter' }
      )
    end

    let(:metric_name) { :ac_in_power }

    before do
      allow(MQTT::Client).to receive(:connect).with(mqtt_params).and_return(mock_mqtt_client)
      allow(mock_mqtt_client).to receive(:publish)
    end

    context 'when hass_klass is "-" (disabled for HA)' do
      it 'returns early and does nothing' do
        allow(metric_definition).to receive(:hass_klass).and_return('-')

        feeder.call(metric_name, metric)
        expect(mock_mqtt_client).not_to have_received(:publish)
      end
    end

    context 'when hass_klass is not "-"' do
      it 'submits hass config on first call and publishes value' do
        feeder.call(metric_name, metric)

        expect(mock_mqtt_client).to have_received(:publish).with(
          a_string_including('config'), # homeassistant/sensor/watti_watchman/ac_in_power___test-meter/config
          kind_of(String)
        ).once

        expect(mock_mqtt_client).to have_received(:publish).with(
          feeder.stat_t('ac_in_power___test-meter'),
          123.5
        ).once
      end

      it 'does not publish a new value if called again before update_interval' do
        feeder.call(metric_name, metric)
        expect(mock_mqtt_client).to have_received(:publish).exactly(2).times

        feeder.call(metric_name, metric)
        expect(mock_mqtt_client).to have_received(:publish).exactly(2).times
      end

      it 'publishes a new value if called after update_interval seconds' do
        feeder.call(metric_name, metric)

        allow(WattiWatchman).to receive(:now).and_return(
          Time.now.to_f + update_interval + 1
        )

        feeder.call(metric_name, metric)
        expect(mock_mqtt_client).to have_received(:publish).exactly(4).times
      end
    end
  end

  describe '#submit_hass_config' do
    let(:mock_mqtt_client) { instance_double(MQTT::Client) }
    let(:metric_definition) do
      double(
        'MetricDefinition',
        hass_klass: 'power',
        metric_id: 'ac_in_power',
        unit: 'W',
        type: 'measurement'
      )
    end
    let(:metric) do
      double(
        'Metric',
        definition: metric_definition,
        value: 123.456,
        _labels: { name: 'test-meter' }
      )
    end

    before do
      allow(MQTT::Client).to receive(:connect).with(mqtt_params).and_return(mock_mqtt_client)
      allow(mock_mqtt_client).to receive(:publish)
    end

    it 'publishes correct config JSON to the correct topic' do
      routing_key = "#{metric_definition.metric_id}___#{metric._labels[:name]}"
      config_topic = "homeassistant/sensor/watti_watchman/#{routing_key}/config"

      feeder.submit_hass_config(:ac_in_power, metric, routing_key)
      expect(mock_mqtt_client).to have_received(:publish).with(
        config_topic,
        kind_of(String)
      )

      args = nil
      expect(mock_mqtt_client).to have_received(:publish).with(config_topic, anything).once do |_, payload|
        args = Oj.load(payload)
      end

      expect(args).to include(
        'name'       => routing_key,
        'stat_t'     => feeder.stat_t(routing_key),
        'uniq_id'    => Digest::SHA256.hexdigest(feeder.stat_t(routing_key)),
        'unit_of_meas' => 'W',
        'stat_cla'   => 'measurement',
        'dev_cla'    => 'power',
        'exp_after'  => 300,
        'dev'        => hash_including('name' => 'WattiWatchman PowerScheduler')
      )
    end
  end

  describe '#stat_t' do
    it 'returns the correct MQTT state topic' do
      routing_key = 'ac_in_power___test-meter'
      expected_topic = "watti_watchman/v#{WattiWatchman::VERSION}/#{routing_key}"
      expect(feeder.stat_t(routing_key)).to eq(expected_topic)
    end
  end
end
