require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'redcarpet'
require 'pry'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

helpers do
  def render_markdown(file_path)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(File.read(file_path))
  end

  def load_file(file_path)
    extension = File.extname(file_path).gsub('.', '')
    case extension
    when 'png', 'jpg'
      headers['Content-Type'] = "image/#{extension}"
      File.read(file_path)
    when 'md'
      erb render_markdown(file_path)
    when 'txt'
      headers['Content-Type'] = 'text/plain'
      File.read(file_path)
    end
  end
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

def load_documents
  pattern = File.join(data_path, '*')
  Dir.glob(pattern).map { |file| File.basename(file) }
end

def valid_credentials?(username, password)
  users = load_user_file
  users.key?(username) &&
    BCrypt::Password.new(users[username]) == password
end

def user_signed_in?
  session.key?(:username)
end

def redirect_signed_out_users
  return if user_signed_in?

  session[:message] = 'You must be signed in to do that.'
  redirect '/'
end

def redirect_unless_admin
  return unless session[:username] == 'admin'

  session[:message] = 'You must be the admin to view that page.'
  redirect '/'
end

def user_yaml_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

def load_user_file
  path = user_yaml_path

  YAML.load_file(path)
end

def write_to_user_file(hash)
  File.open(user_yaml_path, 'w') { |file| file.write(hash.to_yaml) }
end

def registration_errors
  users = load_user_file

  if users.key?(params['username'])
    'That username is already taken'
  elsif params['password'] != params['password-2']
    'Passwords need to match'
  end
end

VALID_EXTENSIONS = ['.txt', '.md', '.jpg', '.png'].freeze

get '/' do
  @documents = load_documents
  @user = session[:username]
  erb :index, layout: :layout
end

get '/users/signin' do
  erb :signin
end

post '/users/signin' do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    status 422
    session[:message] = 'Invalid Credentials'
    erb :signin
  end
end

get '/users/register' do
  erb :register
end

post '/users/register' do
  username = params[:username]
  users = load_user_file

  error = registration_errors
  if error
    session[:message] = error
    erb :register
  else
    password = BCrypt::Password.create(params['password'])
    users[username] = password
    write_to_user_file(users)

    session[:message] = 'User registered!'
    redirect '/'
  end
end

get '/new' do
  redirect_signed_out_users
  erb :new_file, layout: :layout
end

post '/new' do
  redirect_signed_out_users
  filename = params[:filename].to_s.strip
  extension = File.extname(filename)
  if filename.empty?
    session[:message] = 'A name is required.'
    status 422
    erb :new_file, layout: :layout
  elsif !VALID_EXTENSIONS.include?(extension) && !extension.empty?
    session[:message] = "Sorry, only #{VALID_EXTENSIONS.join(' ')} extensions are accepted."
    status 422
    erb :new_file, layout: :layout
  else
    create_document(filename)
    session[:message] = "#{filename} was created"
    redirect '/'
  end
end

post '/new-file' do
end

get '/:filename' do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist"
    redirect '/'
  end
end

get '/:filename/edit' do
  redirect_signed_out_users
  @filename = params[:filename]
  file_path = File.join(data_path, @filename)
  @content = File.read(file_path)
  erb :edit_file, layout: :layout
end

post '/:filename/update' do
  redirect_signed_out_users
  file_path = File.join(data_path, params[:filename])
  File.write(file_path, params[:content])
  session[:message] = "#{params[:filename]} has been updated."
  redirect '/'
end

post '/:filename/delete' do
  redirect_signed_out_users
  @documents = load_documents
  file_path = File.join(data_path, params[:filename])

  if @documents.include?(params[:filename])
    File.delete(file_path)
    session[:message] = "#{params[:filename]} was deleted."
  else
    session[:message] = 'No such file exists to delete'
  end

  redirect '/'
end

post '/:filename/duplicate' do
  filename = params[:filename]
  extension = File.extname(filename)
  root = File.basename(filename, extension)
  filename = "#{root}_dup#{extension}"

  file_path = File.join(data_path, filename)
  create_document(filename)

  dup_content = File.read(File.join(data_path, params[:filename]))
  File.write(file_path, dup_content)

  session[:message] = "#{params[:filename]} has been duplicated."
  redirect '/'
end

post '/signout' do
  session.delete(:username)
  session[:message] = 'You have been signed out.'
  redirect '/'
end
