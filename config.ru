require 'rack'
require 'rackup'
require 'watti_watchman'

WattiWatchman.go

app = Rack::Builder.new do # rubocop:disable Metrics/BlockLength
  map '/metrics' do
    block = lambda do |_env|
      status = 200
      metrics = WattiWatchman::Meter.cache.flat_map do |metric_name, value|

        metric = value["metric"]
        short_metric_name = metric_name[/[^{]+/]
        [
          "#HELP #{short_metric_name} unit #{metric.definition.unit}",
          "#TYPE #{short_metric_name} #{metric.prometheus_type}",
          "#{metric_name} #{metric.value.to_f} #{(metric.timestamp.to_f * 1000).to_i}"
        ]
      end.uniq
      [
        status,
        { 'content-type' => 'text/plain' },
        StringIO.new(metrics.join("\n")+"\n")
      ]
    end

    run block
  end
end.to_app

run app
