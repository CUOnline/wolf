require_relative './test_helper'

class AppTest < Minitest::Test
  def test_get
    get '/'
    assert_equal 200, last_response.status
  end

  def test_not_found
    get '/not-a-route'
    assert_equal 404, last_response.status
    assert_match /Page not found/, last_response.body
  end

  def test_error
    get '/error'
    assert_equal 500, last_response.status
    assert_match /Server error/, last_response.body
  end

  def test_https_redirect
    env 'HTTPS', 'off'

    get '/'
    orig_request = last_request
    assert_equal 301, last_response.status
    assert_equal 'http', last_request.env['rack.url_scheme']

    follow_redirect!
    assert_equal 'https', last_request.env['rack.url_scheme']
    assert_equal orig_request.env['SERVER_NAME'], last_request.env['SERVER_NAME']
    assert_equal orig_request.env['PATH_INFO'], last_request.env['PATH_INFO']
  end

  def test_get_asset
    asset_name = 'wolf_icon.jpg'

    get "/assets/#{asset_name}"
    assert File.exists?(File.join(WolfCore::App.public_folder, asset_name))
    assert_equal 200, last_response.status
  end

  def test_get_asset_not_found
    asset_name = 'nonexistent.jpg'

    get "/assets/#{asset_name}"
    refute File.exists?(File.join(WolfCore::App.public_folder, asset_name))
    assert_equal 404, last_response.status
  end

  def test_settings_override
    default_id = app.settings.canvas_account_id
  end
end
