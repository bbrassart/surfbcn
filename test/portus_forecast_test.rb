ENV['TZ'] = 'Europe/Madrid'

require 'minitest/autorun'
require_relative '../lib/portus_forecast'

class CompassTest < Minitest::Test
  def test_cardinal_points
    assert_equal 'N', PortusForecast::Compass.from_degrees(0)
    assert_equal 'E', PortusForecast::Compass.from_degrees(90)
    assert_equal 'S', PortusForecast::Compass.from_degrees(180)
    assert_equal 'W', PortusForecast::Compass.from_degrees(270)
  end

  def test_sector_boundaries
    assert_equal 'WSW', PortusForecast::Compass.from_degrees(258)
    assert_equal 'W', PortusForecast::Compass.from_degrees(261)
    assert_equal 'W', PortusForecast::Compass.from_degrees(281)
    assert_equal 'WNW', PortusForecast::Compass.from_degrees(283)
    assert_equal 'NW', PortusForecast::Compass.from_degrees(304)
  end

  def test_wraps_around_north
    assert_equal 'N', PortusForecast::Compass.from_degrees(355)
    assert_equal 'N', PortusForecast::Compass.from_degrees(360)
  end
end

class RowTest < Minitest::Test
  def test_wave_direction_is_opposite_to_propagation
    { 0 => ['S', 180], 90 => ['W', 270], 180 => ['N', 0],
      270 => ['E', 90], 360 => ['S', 180], -90 => ['E', 90],
      264 => ['E', 84] }.each do |degrees, (label, from_degrees)|
      row = PortusForecast::Row.new(direction_degrees: degrees)

      assert_equal label, row.direction
      assert_equal from_degrees, row.direction_from_degrees
      assert_equal degrees, row.direction_degrees
    end
  end

  def test_wind_direction_is_not_reversed
    row = PortusForecast::Row.new(wind_direction_degrees: 250)

    assert_equal 'WSW', row.wind_direction
  end
end

class ParseTest < Minitest::Test
  BODY = '[[1792285200.0,0.66,5.1,4.1,264.0],[1792288800.0,0.89,4.7,3.4,261.0]]'.freeze

  def test_parses_rows
    rows = PortusForecast.parse(BODY)

    assert_equal 2, rows.size
    assert_equal '03h00 18-10-2026', rows.first.time.strftime('%Hh%M %d-%m-%Y')
    assert_in_delta 0.66, rows.first.wave_height
    assert_equal 'E', rows.first.direction
    assert_in_delta 84, rows.first.direction_from_degrees
    assert_in_delta 264, rows.first.direction_degrees
  end

  def test_rejects_invalid_json
    assert_raises(PortusForecast::Error) { PortusForecast.parse('Internal Server Error') }
  end

  def test_rejects_empty_payload
    assert_raises(PortusForecast::Error) { PortusForecast.parse('[]') }
  end

  def test_rejects_malformed_entry
    assert_raises(PortusForecast::Error) { PortusForecast.parse('[[1792285200.0,0.66]]') }
  end
end

class ParseWindTest < Minitest::Test
  BODY = '{"hourly":{"time":[1792285200,1792288800],' \
         '"wind_gusts_10m":[12.4,15.0],"wind_direction_10m":[250,262]}}'.freeze

  def test_parses_wind_by_epoch
    wind = PortusForecast.parse_wind(BODY)

    assert_equal({ 1_792_285_200 => [12.4, 250], 1_792_288_800 => [15.0, 262] }, wind)
  end

  def test_rejects_missing_forecast
    assert_raises(PortusForecast::Error) { PortusForecast.parse_wind('{"error":true}') }
  end

  def test_rejects_invalid_json
    assert_raises(PortusForecast::Error) { PortusForecast.parse_wind('nope') }
  end
end

class RenderTest < Minitest::Test
  def test_renders_table_rows
    rows = PortusForecast.parse(ParseTest::BODY)
    rows.first.wind_gust = 12.4
    rows.first.wind_direction_degrees = 250.0
    html = PortusForecast.render(rows: rows, station_name: 'Boya <Test>',
                                 generated_at: Time.at(1_792_290_000))

    assert_includes html, '04h00 18-10-2026'
    assert_includes html, '<td>0.89</td>'
    assert_includes html, '<th>Swell direction</th>'
    assert_includes html, '<td title="81°">E (81°)</td>'
    assert_includes html, '<td>12 kn WSW (250°)</td>'
    assert_includes html, '<td>–</td>'
    assert_includes html, 'Boya &lt;Test&gt;'
    assert_includes html, '<strong id="sun-times" aria-live="polite">Sunrise and sunset: loading...</strong>'
    assert_equal 2, html.scan('<tr data-epoch=').size
  end
end
