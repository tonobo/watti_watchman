require 'rspec'

RSpec.describe WattiWatchman::Meter::MeterClassifier do
  class DummyMeter
    include WattiWatchman::Meter::MeterClassifier
  end

  let(:meter) { DummyMeter.new }
  let(:metric) { double("metric") }

  it '#power_metric_classifier raises an error as it is an abstract method' do
    expect { meter.power_metric_classifier('metric_name') }
      .to raise_error(RuntimeError, "ABSTRACT_METHOD, must be implemented")
  end

  it '#total_power_metric_classifier raises an error as it is an abstract method' do
    expect { meter.total_power_metric_classifier('metric_name') }
      .to raise_error(RuntimeError, "ABSTRACT_METHOD, must be implemented")
  end
end
