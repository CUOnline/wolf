require_relative './test_helper'

class HelpersTest < Minitest::Test
  def test_mount_point
    mount = '/test'
    app.settings.stubs(:mount).returns(mount)
    assert_equal mount, app.mount_point
  end

  def test_mount_point_default
    refute app.respond_to?(:mount)
    assert_equal '/test', app.mount_point
  end

  def test_create_logger
    mount = '/test'
    log_dir = '.'
    app.settings.stubs(:mount).returns(mount)
    app.settings.stubs(:log_dir).returns(log_dir)
    refute File.exists?('./test_log')

    app.create_logger

    assert File.exists?('./test_log')
    File.delete('./test_log')
  end

  def test_create_logger_no_mount
    mount = '/'
    log_dir = '.'
    app.settings.stubs(:mount).returns(mount)
    app.settings.stubs(:log_dir).returns(log_dir)
    refute File.exists?('./wolf_log')

    app.create_logger

    assert File.exists?('./wolf_log')
    File.delete('./wolf_log')
  end


  def test_oauth_callback
    user_id = 123
    user_roles = ['AccountAdmin']
    session = {}
    response = {'user' => {'id' => user_id}}

    app.expects(:session).returns(session)
    app.expects(:user_roles).with(user_id).returns(user_roles)
    session.expects(:[]=).with('user_roles', user_roles)

    app.oauth_callback(response)
  end

  def test_authorized_success
    app.expects(:session).returns({'user_roles' => ['TeacherEnrollment']})
    app.expects(:allowed_roles).returns(['AccountAdmin', 'TeacherEnrollment'])
    assert app.authorized
  end

  def test_authorized_failure
    app.expects(:session).returns({'user_roles' => ['StudentEnrollment']})
    app.expects(:allowed_roles).returns(['AccountAdmin', 'TeacherEnrollment'])
    refute app.authorized
  end

  def test_authorized_no_setting
    app.expects(:session).returns({'user_roles' => ['StudentEnrollment']})
    refute app.authorized
  end


  def test_shard_id
    assert_equal '10430000000000001', app.shard_id(1)
    assert_equal '10430000000000012', app.shard_id(12)
    assert_equal '10430000000000123', app.shard_id(123)
    assert_equal '10430000000001234', app.shard_id(1234)
  end

  def test_valid_lti_request
    provider = mock()
    provider.expects(:valid_request?).returns(true)
    IMS::LTI::ToolProvider.expects(:new).returns(provider)

    assert app.valid_lti_request?(mock('request'), mock('params'))
  end

  def test_invalid_lti_request
    provider = mock()
    provider.expects(:valid_request?).returns(false)
    IMS::LTI::ToolProvider.stubs(:new).returns(provider)

    refute app.valid_lti_request?(mock('request'), mock('params'))
  end

  def test_canvas_api
    canvas_url = 'https://canvasurl.com'
    canvas_token = 'a1b2c3e4f5'
    app.settings.stubs(:canvas_url).returns(canvas_url)
    app.settings.stubs(:canvas_token).returns(canvas_token)
    app.settings.stubs(:api_cache).returns(mock())
    expected_middleware = [
      FaradayMiddleware::OAuth2,
      FaradayMiddleware::ParseJson,
      Faraday::Response::Logger,
      FaradayMiddleware::Caching,
      Faraday::Adapter::Typhoeus
    ]

    api_connection = app.canvas_api

    assert_instance_of(Faraday::Connection, api_connection)
    assert_equal URI("#{canvas_url}/api/v1"), api_connection.url_prefix
    assert_equal expected_middleware, api_connection.builder.handlers.map{|h| h.klass}
  end

  def test_canvas_api_disabled_cache
    canvas_url = 'https://canvasurl.com'
    canvas_token = 'a1b2c3e4f5'
    app.settings.stubs(:canvas_url).returns(canvas_url)
    app.settings.stubs(:canvas_token).returns(canvas_token)
    expected_middleware = [
      FaradayMiddleware::OAuth2,
      FaradayMiddleware::ParseJson,
      Faraday::Response::Logger,
      Faraday::Adapter::Typhoeus
    ]

    api_connection = app.canvas_api

    assert_instance_of(Faraday::Connection, api_connection)
    assert_equal URI("#{canvas_url}/api/v1"), api_connection.url_prefix
    assert_equal expected_middleware, api_connection.builder.handlers.map{|h| h.klass}
  end

  def test_canvas_data
    db = mock()
    cursor = mock()
    query_string = 'SELECT ? FROM user_dim LIMIT ?;'
    params = ['name', 4]
    results = [
      {'name' => 'John'},
      {'name' => 'Paul'},
      {'name' => 'George'},
      {'name' => 'Ringo'}
    ]

    cursor.expects(:execute).with(*params)
    cursor.stubs(:fetch_hash).returns(*results).then.returns(nil)
    cursor.expects(:finish)
    db.expects(:prepare).with(query_string).returns(cursor)
    DBI.expects(:connect).returns(db)

    assert_equal results, app.canvas_data(query_string, *params)
  end

  def test_canvas_data_no_params
    db = mock()
    cursor = mock()
    query_string = 'SELECT * FROM user_dim;'
    results = [ {'name' => 'Ringo'} ]

    cursor.expects(:execute).with(nil)
    cursor.stubs(:fetch_hash).returns(*results).then.returns(nil)
    cursor.expects(:finish)
    db.expects(:prepare).with(query_string).returns(cursor)
    DBI.expects(:connect).returns(db)

    assert_equal results, app.canvas_data(query_string)
  end

  def test_user_roles
    response = OpenStruct.new(:body => [{'role' => 'role1'}, {'role' => 'role3'}])
    api = mock()
    api.stubs(:get => response)
    app.expects(:canvas_api).returns(api)
    app.expects(:canvas_data).returns([{'name' => 'role2'}, {'name' => 'role4'}])
    expected = ['role1', 'role2', 'role3', 'role4']

    assert_equal expected.sort, app.user_roles(1).sort
  end

  def test_enrollment_terms
    response = {'enrollment_terms' => [
      {'name' => 'Spring 2016', 'id' => 1234},
      {'name' => 'Summer 2016', 'id' => 1235},
      {'name' => 'Fall 2016',   'id' => 1236}
    ]}.to_json

    stub_request(:get, /.+\/api\/v1\/accounts\/.+/)
      .to_return(body: response, headers: {'Content-Type' => 'application/json'})

    expected = {
      '1234' => 'Spring 2016',
      '1235' => 'Summer 2016',
      '1236' => 'Fall 2016'
    }

    assert_equal expected, app.enrollment_terms
  end
end
