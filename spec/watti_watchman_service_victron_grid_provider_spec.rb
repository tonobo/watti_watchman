RSpec.describe WattiWatchman::Service::VictronGridProvider do
  let(:mqtt_params) do
    { host: Faker::Internet.ip_v4_address, port: 1883 } 
  end

  let(:with_custom_client_id) do
    Faker::Base.rand(100).odd?
  end

  let(:client_id) do
    next "watti_grid" unless with_custom_client_id

    "watti_#{Faker::Base.rand(100_000)}"
  end

  let(:with_custom_service_name) do
    Faker::Base.rand(100).odd?
  end

  let(:service_name) do
    next "grid_meter" unless with_custom_service_name

    "meter_#{Faker::Base.rand(100_000)}"
  end

  subject do
    args = {mqtt_params: mqtt_params}
    args[:client_id] = client_id if with_custom_client_id
    args[:service_name] = service_name if with_custom_service_name
    described_class.new(**args)
  end

  let(:mqtt_client) do
    double("mqtt-client", host: mqtt_params[:host], port: mqtt_params[:port])
  end

  before(:each) do
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)
  end

  it "#initialize initializes VictronGridProvider object with correct attributes" do
    expect(subject.client_id).to eq(client_id)
    expect(subject.service_name).to eq(service_name)
  end

  it "#initialize raises ArgumentError if mqtt_params is not a hash" do
    expect { described_class.new(mqtt_params: "invalid_params") }.to(
      raise_error(ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()")
    )
  end

  it "#status returns a hash with client ID, version, and service name" do
    expect(subject.status).to eq({
      clientId: client_id,
      version: "WattiWatchman v#{WattiWatchman::VERSION}",
      services: { service_name => "grid"}
    })
  end

  it "#write_prefix subscribes to the correct topic, publishes status, and returns write prefix" do
    expect(subject.mqtt).to receive(:queue_empty?).and_return(false)
    expect(subject.mqtt).to receive(:subscribe).once.with("device/#{client_id}/#")
    expect(subject.mqtt).to receive(:publish).with(
      "device/#{client_id}/Status",
      Oj.dump({
        clientId: client_id,
        version: "WattiWatchman v#{WattiWatchman::VERSION}",
        services: { service_name => :grid },
        connected: 1
      }, mode: :compat)
    ).once
    expect(subject.mqtt).to receive(:get).once
      .and_return(
        [
          "device/#{client_id}/DBus",
          Oj.dump({portalId: :abcd, deviceInstance: { service_name => 3}}, mode: :compat)
        ]
      )
    expect(subject.instance_variable_get(:@write_prefix)).to be_nil
    expect(subject.write_prefix).to eq("W/abcd/grid/3")

    expect(subject.instance_variable_get(:@write_prefix)).to eq("W/abcd/grid/3")
    expect(subject.write_prefix).to eq("W/abcd/grid/3")
  end

  it "#write_prefix reaches timeout on fetch" do
    allow(subject).to receive(:timeout).and_return(0.1)
    expect(subject.mqtt).to receive(:queue_empty?).and_return(true).at_least(2).times
    expect(subject.mqtt).to receive(:subscribe).once.with("device/#{client_id}/#")
    expect(subject.mqtt).to receive(:publish).once
    expect(subject.mqtt).not_to receive(:get)
    expect{subject.write_prefix}.to raise_error(described_class::GridRegisterTimeoutError)
  end

  it "#write_prefix subscribes to the correct topic, publishes invalid status first, and returns write prefix" do
    expect(subject.mqtt).to receive(:queue_empty?).and_return(false, false)
    expect(subject.mqtt).to receive(:subscribe).once.with("device/#{client_id}/#")
    expect(subject.mqtt).to receive(:publish).with(
      "device/#{client_id}/Status",
      Oj.dump({
        clientId: client_id,
        version: "WattiWatchman v#{WattiWatchman::VERSION}",
        services: { service_name => :grid },
        connected: 1
      }, mode: :compat)
    ).once
    expect(subject.mqtt).to receive(:get).once
      .and_return(
        [
          "device/#{client_id}/Moo",
          "",
        ],
        [
          "device/#{client_id}/DBus",
          Oj.dump({portalId: :abcd, deviceInstance: { service_name => 3}}, mode: :compat)
        ]
      )
    expect(subject.instance_variable_get(:@write_prefix)).to be_nil
    expect(subject.write_prefix).to eq("W/abcd/grid/3")

    expect(subject.instance_variable_get(:@write_prefix)).to eq("W/abcd/grid/3")
    expect(subject.write_prefix).to eq("W/abcd/grid/3")
  end

  it "#mqtt returns an instance of MQTT::Client" do
    expect(MQTT::Client).to receive(:connect)
      .once
      .with(
        hash_including(
          host: mqtt_params[:host],
          port: mqtt_params[:port],
          will_payload: /"connected":0/,
          will_topic: "device/#{client_id}/Status"
        )
      )
    expect(subject.instance_variable_get(:@mqtt)).to be_nil
    subject.mqtt

    # just to make sure it has been cached
    expect(subject.instance_variable_get(:@mqtt)).not_to be_nil
    subject.mqtt
  end

end
