# syntax=docker/dockerfile:1
FROM ruby:3-alpine
RUN apk add --no-cache git libcurl ruby-dev build-base libffi-dev && mkdir -p /app/lib/watti_watchman
WORKDIR /app
COPY Gemfile Gemfile.lock watti_watchman.gemspec /app
COPY lib/watti_watchman/version.rb /app/lib/watti_watchman/
RUN bundle install
COPY . /app
CMD bundle exec puma -w 1 -e production -b tcp://0.0.0.0:9292
