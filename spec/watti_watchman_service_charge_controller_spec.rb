RSpec.describe WattiWatchman::Service::ChargeController do
  let(:grid_meter) do
    instance_double("WattiWatchman::Meter::Janitza").tap do
      allow(_1).to receive(:is_a?).with(WattiWatchman::Meter::MeterClassifier)
        .and_return(true)
    end
  end
  let(:battery_meter) do
    instance_double("WattiWatchman::Meter::Janitza").tap do
      allow(_1).to receive(:is_a?).with(WattiWatchman::Meter::MeterClassifier)
        .and_return(true)
    end
  end
  let(:battery_controller) do
    instance_double("WattiWatchman::Meter::Victron").tap do
      allow(_1).to receive(:is_a?).with(WattiWatchman::Meter::BatteryController)
        .and_return(true)
    end
  end
  let(:options) do
    { control_phase: [:l1] }
  end
  subject(:charge_controller) do
    described_class.new(grid_meter: grid_meter,
                        battery_meter: battery_meter,
                        battery_controller: battery_controller,
                        options: options)
  end


  describe "#initialize" do
    context "with valid arguments" do
      it "does not raise any errors" do
        expect { charge_controller }.not_to raise_error
      end
    end

    context "with invalid battery_controller argument" do
      it "raises an ArgumentError" do
        expect {
          described_class.new(grid_meter: grid_meter,
                              battery_meter: battery_meter,
                              battery_controller: "invalid_controller",
                              options: options)
        }.to raise_error(ArgumentError, "battery_controller must implement BatterController interface")
      end
    end

    context "with invalid grid_meter argument" do
      it "raises an ArgumentError" do
        expect {
          described_class.new(grid_meter: "invalid_meter",
                              battery_meter: battery_meter,
                              battery_controller: battery_controller,
                              options: options)
        }.to raise_error(ArgumentError, "grid_meter must implement MeterClassifier interface")
      end
    end

    context "with invalid battery_meter argument" do
      it "raises an ArgumentError" do
        expect {
          described_class.new(grid_meter: grid_meter,
                              battery_meter: "invalid_meter",
                              battery_controller: battery_controller,
                              options: options)
        }.to raise_error(ArgumentError, "battery_meter must implement MeterClassifier interface")
      end
    end
  end

  describe "#call" do
    let(:metric_name) { "some_metric" }
    let(:metric) { double("Metric") }

    before(:each) do
      allow(grid_meter).to receive(:total_power_metric_classifier).with(metric_name)
        .and_return(false)
      allow(battery_meter).to receive(:total_power_metric_classifier).with(metric_name)
        .and_return(false)
      allow(battery_controller).to receive(:battery_soc_classifier).with(metric_name)
        .and_return(false)

      allow(grid_meter).to receive(:total_power).and_return(1000)
      allow(battery_meter).to receive(:total_power).and_return(500)
      allow(battery_controller).to receive(:battery_soc).and_return(50)
    end

    context "when the metric belongs to grid_meter" do
      before do
        allow(grid_meter).to receive(:total_power_metric_classifier).with(metric_name).and_return(true)
      end

      it "sets the setpoint for the battery_controller" do
        expect(battery_controller).to receive(:setpoint).with(value: anything, phase: :l1)
        charge_controller.call(metric_name, metric)
      end
    end

    context "when the metric belongs to battery_meter" do
      before do
        allow(battery_meter).to receive(:total_power_metric_classifier).with(metric_name).and_return(true)
      end

      it "sets the setpoint for the battery_controller" do
        expect(battery_controller).to receive(:setpoint).with(value: anything, phase: :l1)
        charge_controller.call(metric_name, metric)
      end
    end

    context "when the metric belongs to battery_meter but configured as three-phase model" do
      before do
        allow(battery_meter).to receive(:total_power_metric_classifier).with(metric_name).and_return(true)
        allow(charge_controller).to receive(:setpoint).and_return(1200)
      end

      let :options do
        { control_phase: %w(l1 l2 l3) }
      end

      it "sets the setpoint for the battery_controller" do
        expect(battery_controller).to receive(:setpoint).with(value: 400, phase: 'l1')
        expect(battery_controller).to receive(:setpoint).with(value: 400, phase: 'l2')
        expect(battery_controller).to receive(:setpoint).with(value: 400, phase: 'l3')
        charge_controller.call(metric_name, metric)
      end
    end

    context "when the metric belongs to battery_controller" do
      before do
        allow(battery_controller).to receive(:battery_soc_classifier).with(metric_name).and_return(true)
      end

      it "sets the setpoint for the battery_controller" do
        expect(battery_controller).to receive(:setpoint).with(value: anything, phase: :l1)
        charge_controller.call(metric_name, metric)
      end
    end

    context "when the metric does not belong to any relevant component" do
      it "does not set the setpoint for the battery_controller" do
        expect(battery_controller).not_to receive(:setpoint)
        charge_controller.call(metric_name, metric)
      end
    end
  end

  describe "#setpoint" do
    def total_setpoint!(grid:, battery:, soc:)
      soc = Faker::Base.rand(soc) unless soc.is_a?(Numeric)
      allow(grid_meter).to receive(:total_power).and_return(grid)
      allow(battery_meter).to receive(:total_power).and_return(battery)
      allow(battery_controller).to receive(:battery_soc).and_return(soc)
    end

    def setpoint!(phase:, grid:, battery:, soc:)
      soc = Faker::Base.rand(soc) unless soc.is_a?(Numeric)
      allow(grid_meter).to receive(:power).with(phase: phase).and_return(grid)
      allow(battery_meter).to receive(:power).with(phase: phase).and_return(battery)
      allow(battery_controller).to receive(:battery_soc).and_return(soc)
    end

    context "when discharge is expected" do
      it "feeds 1000W to grid as it is exact difference" do
        total_setpoint!(grid: 1000, battery: 0, soc: 30..100)
        expect(charge_controller.setpoint).to eq(-1000)
      end

      it "feeds 2000W to grid as it's the defined threshold" do
        total_setpoint!(grid: 3500, battery: 0, soc: 30..100)
        expect(charge_controller.setpoint).to eq(-2000)
      end

      it "feeds 2000W to grid as it's the defined threshold and starts with battery offset" do
        total_setpoint!(grid: 4500, battery: 1000, soc: 30..100)
        expect(charge_controller.setpoint).to eq(-2000)
      end

      it "feeds 1000W to grid as the soc threshold hits <10%" do
        total_setpoint!(grid: 3500, battery: 0, soc: 5...10.0)
        expect(charge_controller.setpoint).to eq(-1000)
      end

      it "feeds 0W to grid as the soc threshold hits <5%" do
        total_setpoint!(grid: 3500, battery: 0, soc: 0...5.0)
        expect(charge_controller.setpoint).to eq(0)
      end
    end

    context "when charge is expected" do
      it "loads 1000W from grid as it is exact difference" do
        total_setpoint!(grid: -1000, battery: 0, soc: 30...90)
        expect(charge_controller.setpoint).to eq(1000)
      end

      it "loads 3000W from grid as it's the defined threshold" do
        total_setpoint!(grid: -3500, battery: 0, soc: 30...90)
        expect(charge_controller.setpoint).to eq(3000)
      end

      it "loads 3000W from grid as it's the defined threshold and starts with battery offset" do
        total_setpoint!(grid: -4500, battery: 1000, soc: 30...90)
        expect(charge_controller.setpoint).to eq(3000)
      end

      it "loads 1000W from grid as the soc threshold hits >90%" do
        total_setpoint!(grid: -3500, battery: 0, soc: 90...97.0)
        expect(charge_controller.setpoint).to eq(1000)
      end

      it "loads 0W from grid as the soc threshold hits >97%" do
        total_setpoint!(grid: -3500, battery: 0, soc: 97..100.0)
        expect(charge_controller.setpoint).to eq(500)
      end
    end
  end
end

