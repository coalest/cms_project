ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require 'bcrypt'

require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    create_document('../users.yml', "{ admin: $2a$12$O6kr1mLZHmfNm8Vl/mSpqOQrb0gF7cwh1REi9jEKgt.DkUBD0kqUm }")
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end
  
  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/", {}, {"rack.session" => { username: "admin", password: "secret"} }

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_file_contents
    text = <<~TEXT
      1993 - Yukihiro Matsumoto dreams up Ruby.
      1995 - Ruby 0.95 released.
      1996 - Ruby 1.0 released.
      1998 - Ruby 1.2 released.
      1999 - Ruby 1.4 released.
      2000 - Ruby 1.6 released.
      2003 - Ruby 1.8 released.
      2007 - Ruby 1.9 released.
      2013 - Ruby 2.0 released.
      2013 - Ruby 2.1 released.
      2014 - Ruby 2.2 released.
      2015 - Ruby 2.3 released.
      2016 - Ruby 2.4 released.
      2017 - Ruby 2.5 released.
      2018 - Ruby 2.6 released.
      2019 - Ruby 2.7 released.
    TEXT

    create_document "history.txt", text
    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]

    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_file_doesnt_exist
    get "/dawn_of_everything.epub", {}, {"rack.session" => { username: "admin", password: "secret"} }
    assert_equal 302, last_response.status

    assert_equal "dawn_of_everything.epub does not exist", session[:message]
  end

  def test_markdown_file_contents
    text = <<~MD
      # Ruby is ...

      A dynamic, open source programming language with a focuse on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write.
    MD

    create_document "about.md", text
    get "/about.md"
    assert_equal 200, last_response.status
    refute_includes last_response.body, "#"
    assert_includes last_response.body, "Ruby is"
  end

  def test_file_edit
    create_document "about.md"

    get "/about.md/edit", {}, admin_session
    assert_equal 200, last_response.status
  end

  def test_updating_document
    post "/users/signin", {}, admin_session
    create_document "changes.txt"
    post "/changes.txt/update", content: "new content"

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_page
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Create a new text document:"
  end

  def test_new_document
    post "/users/signin", {}, admin_session
    post "/new", filename:"new.md"
    assert_equal 302, last_response.status
    assert_equal "new.md was created", session[:message]
    get last_response["Location"]
    assert_includes last_response.body, ">new.md<"
  end

  def test_create_new_document_without_filename
    post "/new", {},  { filename: "", "rack.session" => { username: "admin" } }
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_delete_button
    post "/users/signin", {}, admin_session
    create_document "test.md"
    post "/test.md/delete"
    assert_equal 302, last_response.status
    assert_equal "test.md was deleted.", session[:message]

    post "/users/signin", {}, admin_session
    get "/"
    refute_includes last_response.body, "test.md"
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status

    assert_equal "Welcome!", session[:message]
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "guest", password: "shhhh"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/signout"
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end

  def test_signed_out_privileges
    get "/new"
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    post "/new", {},  { filename: "test.txt" }
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    create_document "test.txt"
    get "/test.txt/edit"
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    post "/test.txt/update"
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    post "test.txt/delete"
    assert_equal "You must be signed in to do that.", session[:message]
  end
end
