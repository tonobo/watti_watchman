RSpec.describe WattiWatchman::Logger::ThrottledLogger do
  let(:log_output) { StringIO.new }
  let(:throttle_interval) { 5 }
  let(:max_errors) { 3 }

  subject(:logger) do
    described_class.new(
      log_output,
      throttle_interval: throttle_interval,
      max_errors: max_errors
    )
  end

  before do
    logger.level = ::Logger::DEBUG
    allow(WattiWatchman).to receive(:now).and_return(1000.0)
  end

  def logged_output
    log_output.string
  end

  describe "basic throttling" do
    it "logs the first message immediately" do
      logger.info("Hello")
      expect(logged_output).to include("Hello")
    end

    it "does not log a second time within throttle_interval" do
      logger.info("Hello")
      expect(logged_output).to include("Hello")

      logger.info("Hello")
      expect(logged_output.scan("Hello").size).to eq(1)
    end

    it "logs again after throttle_interval, mentioning suppressed logs" do
      logger.info("Hello")
      logger.info("Hello")
      logger.info("Hello")

      expect(logged_output.scan("Hello").size).to eq(1)
      log_output.truncate(0)
      log_output.rewind

      allow(WattiWatchman).to receive(:now).and_return(1000.0 + throttle_interval + 0.1)
      logger.info("Hello")

      expect(logged_output).to include("Hello (suppressed 2 logs)")
    end
  end

  describe "max_errors" do
    it "removes oldest entries if more than max_errors distinct messages occur" do
      logger.warn("Msg1")
      logger.warn("Msg2")
      logger.warn("Msg3")

      expect(logged_output).to include("Msg1")
      expect(logged_output).to include("Msg2")
      expect(logged_output).to include("Msg3")

      log_output.truncate(0)
      log_output.rewind

      logger.warn("Msg4") 
      allow(WattiWatchman).to receive(:now).and_return(1000.0 + throttle_interval + 0.1)

      logger.warn("Msg1 again")
      expect(logged_output).to include("Msg1 again")
    end
  end

  describe "#add" do
    it "works with block form" do
      logger.info { "Block message" }
      expect(logged_output).to include("Block message")
    end
  end
end
