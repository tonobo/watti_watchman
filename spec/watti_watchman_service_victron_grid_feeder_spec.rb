require 'rspec'

RSpec.describe WattiWatchman::Service::VictronGridFeeder do
  let(:grid_meter) do
    instance_double(
      WattiWatchman::Meter::Janitza,
      is_a?: WattiWatchman::Meter::MeterClassifier,
    )
  end
  let(:mqtt_params) { { host: "localhost", port: 1883 } }
  let(:write_prefix) { "W/portal1/grid/device1" }
  let(:options) { { power_update_frequency: 0.2, common_update_frequency: 1.0 } }
  let(:mqtt_client) { double("mqtt-client") }

  subject(:victron_grid_feeder) do
    described_class.new(
      mqtt_params: mqtt_params,
      grid_meter: grid_meter,
      write_prefix: write_prefix,
      options: options
    )
  end

  before(:each) do
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)
  end

  describe "#initialize" do
    context "with valid parameters" do
      it "initializes successfully" do
        expect { victron_grid_feeder }.not_to raise_error
      end
    end

    context "with invalid grid_meter" do
      let(:grid_meter) { "invalid_meter" }

      it "raises an ArgumentError" do
        expect { victron_grid_feeder }.to raise_error(
          ArgumentError, "grid_meter should embed MeterClassifier"
        )
      end
    end

    context "with invalid mqtt_params" do
      let(:mqtt_params) { "invalid_params" }

      it "raises an ArgumentError" do
        expect { victron_grid_feeder }.to raise_error(
          ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()"
        )
      end
    end
  end

  describe "#call" do
    let(:metric) do
      instance_double(WattiWatchman::Meter::Metric,
                      origin: grid_meter,
                      cache: {},
                      value: Faker::Base.rand(1..1000.0),
                      definition: metric_definition)
    end

    context "when metric update belongs to be an non grid_meter" do
      let(:metric) do
        instance_double(WattiWatchman::Meter::Metric,
                        origin: double("random-origin"),
                        cache: {},
                        definition: double("random-metric"))
      end

      it "does not publish the metric" do
        expect(victron_grid_feeder.mqtt).not_to receive(:publish)

        victron_grid_feeder.call("moo", metric)
      end
    end

    context "when metric update belongs to be definition with regex topic" do
      let(:metric_name) { %Q(victron_dc_soc) } 
      let(:metric_definition) { WattiWatchman::Meter::Victron::Registers.fetch(%r(/vebus/\d+/Soc$)) }

      it "does not publish the metric" do
        expect(victron_grid_feeder.mqtt).not_to receive(:publish)

        victron_grid_feeder.call(metric_name, metric)
      end
    end

    context "when metric update belongs to be skippable by topic definition" do
      let(:metric_name) { %Q(janitza_real_energy_l1_total) } 
      let(:metric_definition) { WattiWatchman::Meter::Janitza::Registers[27] }

      it "does not publish the metric" do
        expect(grid_meter).not_to receive(:power_metric_classifier)
        expect(grid_meter).not_to receive(:total_power_metric_classifier)

        expect(victron_grid_feeder.mqtt).not_to receive(:publish)

        victron_grid_feeder.call(metric_name, metric)
        expect(metric.cache).to be_empty
      end
    end

    context "when metric update belongs to the same device with power_metric with phase label" do
      let(:metric_name) { %Q(janitza_real_power{phase="l1"}) } 
      let(:metric_definition) { WattiWatchman::Meter::Janitza::Registers[10] }

      it "publishes the metric to MQTT" do
        expect(grid_meter).to receive(:power_metric_classifier)
          .exactly(3).times
          .and_return("l1")

        # this will be skipped as the more specific phase matcher applied first
        expect(grid_meter).not_to receive(:total_power_metric_classifier)

        expect(victron_grid_feeder.mqtt).to receive(:publish).with(
          "#{write_prefix}/Ac/L1/Power", a_kind_of(String)
        ).twice

        before = WattiWatchman.now
        victron_grid_feeder.call(metric_name, metric)
        expect(metric.cache).to include("last_grid_forward")
        expect(metric.cache["last_grid_forward"]).to be_between(before, WattiWatchman.now)

        # should be skipped due to instant re-call
        victron_grid_feeder.call(metric_name, metric)
        sleep 0.2
        victron_grid_feeder.call(metric_name, metric)
      end
    end

    context "when metric update belongs to the same device with total_power_metric" do
      let(:metric_name) { %Q(janitza_real_power_total) } 
      let(:metric_definition) { WattiWatchman::Meter::Janitza::Registers[13] }

      it "publishes the metric to MQTT" do
        expect(grid_meter).to receive(:power_metric_classifier)
          .exactly(3).times
          .and_return(nil)
        expect(grid_meter).to receive(:total_power_metric_classifier)
          .exactly(3).times
          .and_return(true)

        expect(victron_grid_feeder.options).to receive(:fetch)
          .with(:common_update_frequency)
          .exactly(3).times
          .and_return(options[:common_update_frequency])
        expect(victron_grid_feeder.options).to receive(:fetch)
          .with(:power_update_frequency)
          .exactly(3).times
          .and_return(options[:power_update_frequency])

        expect(victron_grid_feeder.mqtt).to receive(:publish).with(
          "#{write_prefix}/Ac/Power", a_kind_of(String)
        ).once

        victron_grid_feeder.call(metric_name, metric)
        victron_grid_feeder.call(metric_name, metric)
        victron_grid_feeder.call(metric_name, metric)
      end
    end

    context "when metric update belongs to the same device with an exportable common metric" do
      let(:metric_name) { %Q(janitza_voltage{phase="l1"}) } 
      let(:metric_definition) { WattiWatchman::Meter::Janitza::Registers[0] }

      it "publishes the metric to MQTT" do
        expect(grid_meter).to receive(:power_metric_classifier)
          .exactly(3).times
          .and_return(nil)
        expect(grid_meter).to receive(:total_power_metric_classifier)
          .exactly(3).times
          .and_return(false)

        expect(victron_grid_feeder.options).to receive(:fetch)
          .with(:common_update_frequency)
          .exactly(3).times
          .and_return(options[:common_update_frequency])
        expect(victron_grid_feeder.options).not_to receive(:fetch)
          .with(:power_update_frequency)

        expect(victron_grid_feeder.mqtt).to receive(:publish).with(
          "#{write_prefix}/Ac/L1/Voltage", a_kind_of(String)
        ).once

        victron_grid_feeder.call(metric_name, metric)
        victron_grid_feeder.call(metric_name, metric)
        victron_grid_feeder.call(metric_name, metric)
      end
    end
  end
end

