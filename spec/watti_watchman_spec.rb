# frozen_string_literal: true

RSpec.describe WattiWatchman do
  it "has a version number" do
    expect(WattiWatchman::VERSION).not_to be nil
  end

  it "returns actual monotonic clock stamp" do
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(Process).to receive(:clock_gettime)
      .twice
      .with(anything)
      .and_call_original
    stamp = WattiWatchman.now
    after = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(stamp).to be > before
    expect(stamp).to be < after
  end

  it "injects customs logger" do
    WattiWatchman.logger.info "MooOOoo" 
    expect(unit_logger.string).to include("MooOOoo")
  end
end
