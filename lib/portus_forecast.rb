require 'erb'
require 'json'
require 'net/http'
require 'uri'

# Fetches the hourly wave forecast of a Puertos del Estado (Portus) buoy and
# renders it as a static HTML table.
module PortusForecast
  API_BASE = 'https://poem.puertos.es/portus/ForecastData'.freeze
  FIELDS = %w[Datetime Hm0 Tp Tm02 MeanDir180].freeze
  OPEN_METEO_URL = 'https://api.open-meteo.com/v1/forecast'.freeze
  TEMPLATE_PATH = File.expand_path('../templates/index.html.erb', __dir__)

  class Error < StandardError; end

  module Compass
    POINTS = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW].freeze
    SECTOR_SIZE = 360.0 / POINTS.size

    # @param degrees [Numeric] direction in degrees (0 = N, clockwise)
    # @return [String] 16-point compass label, e.g. "WSW"
    def self.from_degrees(degrees)
      POINTS[(degrees / SECTOR_SIZE).round % POINTS.size]
    end
  end

  Row = Struct.new(:time, :wave_height, :peak_period, :mean_period, :direction_degrees,
                   :wind_gust, :wind_direction_degrees, keyword_init: true) do
    # @return [Numeric] direction waves come from (0 = N, clockwise)
    def direction_from_degrees
      (direction_degrees + 180) % 360
    end

    # @return [String] direction waves come from as a compass label
    def direction
      Compass.from_degrees(direction_from_degrees)
    end

    # @return [String] direction the wind blows from as a compass label
    def wind_direction
      Compass.from_degrees(wind_direction_degrees)
    end
  end

  class << self
    # @param code [String] Portus point code (e.g. "712018020")
    # @param scheme [String] forecast model scheme (e.g. "Siwana")
    # @return [Array<Row>] hourly forecast rows, oldest first
    def fetch(code:, scheme:)
      uri = URI("#{API_BASE}/#{scheme}/forecast")
      uri.query = URI.encode_www_form(code: code, fields: FIELDS.join(','))
      parse(get(uri))
    end

    # @param body [String] JSON returned by the forecast endpoint
    # @return [Array<Row>]
    def parse(body)
      data = JSON.parse(body)
      raise Error, 'Unexpected forecast payload' unless data.is_a?(Array) && data.any?

      data.map { |entry| build_row(entry) }
    rescue JSON::ParserError => e
      raise Error, "Invalid forecast JSON: #{e.message}"
    end

    # @param lat [Numeric]
    # @param lon [Numeric]
    # @return [Hash{Integer => Array(Float, Float)}] [gust knots, direction degrees] keyed by epoch seconds
    def fetch_wind(lat:, lon:)
      uri = URI(OPEN_METEO_URL)
      uri.query = URI.encode_www_form(latitude: lat, longitude: lon,
                                      hourly: 'wind_gusts_10m,wind_direction_10m',
                                      wind_speed_unit: 'kn', timeformat: 'unixtime')
      parse_wind(get(uri))
    end

    # @param body [String] JSON returned by the Open-Meteo forecast endpoint
    # @return [Hash{Integer => Array(Float, Float)}]
    def parse_wind(body)
      hourly = JSON.parse(body)['hourly']
      raise Error, 'Unexpected Open-Meteo payload' unless hourly.is_a?(Hash) && hourly['time'].is_a?(Array)

      values = Array(hourly['wind_gusts_10m']).zip(Array(hourly['wind_direction_10m']))
      hourly['time'].zip(values).to_h
    rescue JSON::ParserError => e
      raise Error, "Invalid Open-Meteo JSON: #{e.message}"
    end

    # @param rows [Array<Row>]
    # @param station_name [String]
    # @param generated_at [Time]
    # @return [String] full HTML document
    def render(rows:, station_name:, generated_at:)
      ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-').result(binding)
    end

    private

    def get(uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                     open_timeout: 15, read_timeout: 30) do |http|
        http.get(uri.request_uri)
      end
      raise Error, "#{uri.host} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def build_row(entry)
      unless entry.is_a?(Array) && entry.size == FIELDS.size
        raise Error, "Unexpected forecast entry: #{entry.inspect}"
      end

      epoch, wave_height, peak_period, mean_period, direction = entry
      Row.new(time: Time.at(epoch), wave_height: wave_height, peak_period: peak_period,
              mean_period: mean_period, direction_degrees: direction)
    end

    def h(text)
      ERB::Util.html_escape(text)
    end
  end
end
