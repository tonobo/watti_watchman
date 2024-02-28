require 'thread'

RSpec.describe WattiWatchman::Meter::Victron do

  let(:mqtt_cache_to_server) { Queue.new }
  let(:mqtt_cache_to_client) { Queue.new }

  let :mqttc do
    double("mqtt-client").tap do |mc|
      allow(mc).to receive(:publish) do |topic, message|
        mqtt_cache_to_server << { topic: topic, message: message.to_s }
      end
      allow(mc).to receive(:queue_empty?) do
        mqtt_cache_to_client.empty?
      end
      allow(mc).to receive(:subscribe)
      allow(mc).to receive(:get) do
        # { topic: <string>, message: <string> }
        # => [<topic>, <message>]
        mqtt_cache_to_client.pop.values
      end
    end
  end

  let(:vrm_id) { Faker::Crypto.sha1[0..12] }
  let(:vebus_id) { Faker::Base.rand(200..290).to_s }
  let(:name) { "moo" }

  def veregister(path, value)
    mqtt_cache_to_client << { 
      topic: "N/#{vrm_id}/vebus/#{vebus_id}/#{path}",
      message: Oj.dump({value: value}, mode: :compat)
    }
  end

  include_context "meter"

  subject do
    described_class.new(name: name, id: vrm_id, mqtt_params: {}).tap do
      allow(_1).to receive(:mqtt).and_return(mqttc)
    end
  end

  context "single iteration" do
    before(:each) { iterations(1) }

    it "handles initial keepalive" do
      subject.do
      expect(mqtt_cache_to_server).to_not be_empty
      expect(mqtt_cache_to_server.pop).to match({topic: "R/#{vrm_id}/keepalive",message: anything})
    end

    it "handles initial subscribe" do
      expect(mqttc).to receive(:subscribe).with("N/#{vrm_id}/#")
      subject.do
    end

    it "handles dicovers vebus_id" do
      veregister("Dc/0/Power", 12)
      expect(subject.vebus_id).to be_nil
      subject.do
      expect(subject.vebus_id).to eq(vebus_id)
    end

    it "registers common message_*" do
      veregister("Dc/0/Power", 12)
      subject.do
      expect(mcache).to include(%Q(victron_messages_consumed_total{name="#{name}",id="#{vrm_id}"}))
      expect(mcache).to include(%Q(victron_messages_processed_total{name="#{name}",id="#{vrm_id}"}))
      expect(mcache.keys.to_s).not_to include("victron_messages_payload_invalid_total")
      expect(mcache.keys.to_s).not_to include("victron_messages_value_null_total")
    end

    it "registers common message_value_null" do
      veregister("Dc/0/Power", nil)
      veregister("Ac/ActiveIn/L1/P", nil)
      subject.do
      expect(mcache).to include(%Q(victron_messages_consumed_total{name="#{name}",id="#{vrm_id}"}))
      expect(mcache).to include(
        %Q(victron_messages_value_null_total{name="#{name}",id="#{vrm_id}",definition="victron_dc_power"}))
      expect(mcache).to include(
        %Q(victron_messages_value_null_total{name="#{name}",id="#{vrm_id}",definition="victron_ac_in_power_l1"}))
      expect(mcache.keys.to_s).not_to include("victron_messages_processed_total")
    end
  end

  it "handles resubscribe" do
    iterations(15)
    allow(subject).to receive(:keepalive_interval).and_return(0.1)
    subject.do
    expect(mqtt_cache_to_server).to_not be_empty
    expect(mqtt_cache_to_server.pop).to match({topic: "R/#{vrm_id}/keepalive", message: anything})
    expect(mqtt_cache_to_server.pop).to match({topic: "R/#{vrm_id}/keepalive", message: anything})
    expect(mqtt_cache_to_server).to be_empty
  end
end
