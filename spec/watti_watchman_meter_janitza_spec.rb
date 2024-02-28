
RSpec.describe WattiWatchman::Meter::Janitza do
  let :registers do
    [
      233.8685760498047, # V lx_n
      236.64195251464844,
      234.98904418945312,

      407.46051025390625, # V lx_lx
      407.853515625,
      406.6347961425781,

      3.5721144676208496, # current lx
      2.1518187522888184,
      4.613165378570557,
      3.554508924484253, # current total

      614.0399780273438, # power lx
      319.261962890625,
      1000.9397583007812,
      1934.24169921875, # power total

      835.4053344726562, # VA lx
      509.2106018066406,
      1084.0433349609375,
      2428.6591796875, # VA total

      -324.7113342285156, # var lx
      -363.46734619140625,
      -376.793701171875,
      -1064.972412109375, # var total

      0.8861088156700134, # power facotr lx
      0.6615726947784424,
      0.9361423850059509,

      50.01308059692383, # frequency

      1.0, # rotation field

      12910043.0, # energy lx
      10726793.0,
      10862500.0,
      34515072.0, # energy total

      12987790.0, # consumed lx
      10813795.0,
      10952704.0,
      34739176.0, # consumed total

      61593.81640625, # delivered lx
      81384.3828125,
      86986.359375,
      193044.84375 # delivered total
    ]
  end

  let(:name) { Faker::Base.sample(%w(hak uvt moo))}
  let(:host) { Faker::Internet.private_ip_v4_address }
  let(:port) { Faker::Base.rand(500...600) }
  let(:unit) { Faker::Base.rand(1..30) }

  def new_modbus_slave_object(latency: 0)
    double("modbus-slave-object").tap do |slave|
      allow(slave).to receive(:query)
        .with([3, 19000, registers.size * 2].pack("cn*")) do
          sleep(latency) if latency > 0
          registers.pack("g*")
        end
    end
  end

  let :modbus_slave_object do
    new_modbus_slave_object
  end

  let :modbus_client do
    double("modbus-client").tap do |client|
      allow(client).to receive(:with_slave)
        .with(unit)
        .and_yield(modbus_slave_object)
    end
  end

  before(:each) do
    allow(ModBus::TCPClient).to receive(:new)
      .with(host, port)
      .and_yield(modbus_client)
  end

  include_context "meter" 

  subject do
    described_class.new(name: name, host: host, port: port, unit: unit)
  end

  it "creates processing metrics" do
    iterations(1)
    subject.do() 
    expect(mcache.keys).to include(%Q(janitza_processing_registers_seconds_total{name="#{name}"}))
    expect(mcache.keys).to include(%Q(janitza_processing_registers_count_total{name="#{name}"}))
    expect(mcache.keys).to include(%Q(janitza_collecting_registers_seconds_total{name="#{name}"}))
    expect(mcache.keys.join(" ")).to_not include("pressure_count_total")

    register_count_metric = mcache[%Q(janitza_processing_registers_count_total{name="#{name}"})]
    expect(register_count_metric["metric"]).to be_a WattiWatchman::Meter::Metric
    expect(register_count_metric["metric"].value).to eq(registers.size)
  end

  it "failed loading registers from device, query returned nil" do
    iterations(1)
    expect(modbus_slave_object).to receive(:query).and_return(nil)
    subject.do() 
    metric = mcache[%Q(janitza_processing_errors_count_total{name="#{name}",error="register_query_error"})]
    expect(metric["metric"]&.value).to eq(1.0)
    expect{subject.total_power}.to raise_error(WattiWatchman::Meter::PowerMetricNotFoundError) 

    iterations(1)
    subject.do() 
    expect(subject.total_power).to eq(registers[13])
  end

  it "requested amount of registers doesn't match returned value (happend on modbus-tcp -> modbus-rtu gw)" do
    iterations(1)
    expect(modbus_slave_object).to receive(:query)
      .and_return((registers[0..3] + registers).pack("g*"))
    subject.do() 
    puts unit_logger.string
    metric = mcache[%Q(janitza_processing_errors_count_total{name="#{name}",error="register_overrun"})]
    expect(metric["metric"]&.value).to eq(1.0)
    expect{subject.total_power}.to raise_error(WattiWatchman::Meter::PowerMetricNotFoundError) 

    iterations(1)
    subject.do() 
    expect(subject.total_power).to eq(registers[13])
  end

  { 
    RuntimeError => "unkown_error", 
    ModBus::Errors::ModBusTimeout => "modbus_timeout", 
    ModBus::Errors::ModBusException => "unkown_modbus_error"
  }.each do |error_class, error_string|
    it "failed loading registers from device, query raised an #{error_class}" do
      iterations(1)
      expect(modbus_slave_object).to receive(:query).and_raise(error_class)
      subject.do() 
      metric = mcache[%Q(janitza_processing_errors_count_total{name="#{name}",error="#{error_string}"})]
      expect(metric["metric"]&.value).to eq(1.0)
      expect{subject.total_power}.to raise_error(WattiWatchman::Meter::PowerMetricNotFoundError) 

      iterations(1)
      subject.do() 
      expect(subject.total_power).to eq(registers[13])
    end
  end

  it "has correct volatage in cache" do
    start_time = Time.now
    iterations(1)
    subject.do() 
    register_count_metric = mcache[%Q(janitza_voltage{name="#{name}",phase="l1"})]
    expect(register_count_metric).not_to be_nil
    expect(register_count_metric["metric"]).to be_a WattiWatchman::Meter::Metric
    expect(register_count_metric["metric"].value).to eq(registers.first)
    expect(register_count_metric["metric"].timestamp).to be_between(start_time.to_f, Time.now.to_f)
  end

  context "power metric collection interface" do
    it "searches for power metric" do
      expect{subject.power(phase: "L1")}.to(
        raise_error(WattiWatchman::Meter::PowerMetricNotFoundError)  
      )
    end

    it "searched for power metric which is outdated" do
      iterations(1)
      subject.do() 
      sleep(0.2)
      expect{subject.power(phase: "L1", max_age: 0.1)}.to(
        raise_error(WattiWatchman::Meter::PowerMetricOutdatedError)  
      )
      expect(subject.power(phase: "L1", max_age: 1)).to eq(registers[10])
    end

    it "finds power metric for phase" do
      iterations(1)
      subject.do() 
      expect(subject.power(phase: "L1")).to eq(registers[10])
    end

    it "searches for total power metric" do
      expect{subject.total_power}.to(
        raise_error(WattiWatchman::Meter::PowerMetricNotFoundError)  
      )
    end

    it "searched for total power metric which is outdated" do
      iterations(1)
      subject.do() 
      sleep(0.2)
      expect{subject.total_power(max_age: 0.1)}.to(
        raise_error(WattiWatchman::Meter::PowerMetricOutdatedError)  
      )
      expect(subject.total_power(max_age: 1)).to eq(registers[13])
    end

    it "finds total power metric for phase" do
      iterations(1)
      subject.do() 
      expect(subject.total_power(max_age: 1)).to eq(registers[13])
    end
  end

  context "power metric classification" do
    before(:each) do
      iterations(1)
      subject.do() 
    end

    it "ignored non power metric" do
      metric_name = %Q(janitza_voltage{name="#{name}",phase="l1"})
      voltage_metric = mcache[metric_name]
      expect(voltage_metric).not_to be_nil
      expect(subject.power_metric_classifier(metric_name)).to be_nil
      expect(subject.total_power_metric_classifier(metric_name)).to be_falsey
    end

    it "returns phase from phase based power tracking metric" do
      metric_name = %Q(janitza_real_power{name="#{name}",phase="l2"})
      power_metric = mcache[metric_name]
      expect(power_metric).not_to be_nil
      expect(subject.power_metric_classifier(metric_name)).to eq("l2")
      expect(subject.total_power_metric_classifier(metric_name)).to be_falsey
    end

    it "returns true from total power tracking metric" do
      metric_name = %Q(janitza_real_power_total{name="#{name}"})
      power_metric = mcache[metric_name]
      expect(power_metric).not_to be_nil
      expect(subject.power_metric_classifier(metric_name)).to be_nil
      expect(subject.total_power_metric_classifier(metric_name)).to be_truthy
    end

  end

  it "handles persistent increment of processing metrics" do
    start_time = Time.now
    iterations(3)
    subject.do() 
    register_count_metric = mcache[%Q(janitza_processing_registers_count_total{name="#{name}"})]
    expect(register_count_metric["metric"].value).to eq(3*registers.size)
    expect(register_count_metric["metric"].timestamp).to be_between(start_time.to_f, Time.now.to_f)
  end

  context "slow modbus client" do
    let :latency do
      0.11
    end

    let :modbus_slave_object do
      new_modbus_slave_object(latency: latency)
    end

    it "can handle slow requests" do
      iterations(2)
      subject.do() 
      expect(mcache.keys).to include(%Q(janitza_collecting_registers_pressure_count_total{name="#{name}"}))
      register_count_metric = mcache[%Q(janitza_processing_registers_count_total{name="#{name}"})]
      expect(register_count_metric["metric"].value).to eq(2*registers.size)
      register_seconds_metric = mcache[%Q(janitza_processing_registers_seconds_total{name="#{name}"})]
      expect(register_seconds_metric["metric"].value).to be > (2*latency)
    end
  end


  it "verify mcache emptyness" do
    expect(mcache).to eq(Hash.new)
  end

end
