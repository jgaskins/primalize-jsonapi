require 'benchmark/ips'
$:.unshift 'lib'
$:.unshift '../active_model_serializers/lib'
require 'active_model_serializers'
require 'primalize/jsonapi'
require 'grand_central/model'
require 'ffaker'

class Model < GrandCentral::Model
  def read_attribute_for_serialization attr
    public_send attr
  end
end

class Article < Model
  attributes :id, :title, :body, :view_count, :author, :comments
end

class Person < Model
  attributes :id, :name, :email
end

class Comment < Model
  attributes :id, :body, :author
end

class ArticlePrimalizer < Primalize::JSONAPI[:articles]
  attributes(
    title: string,
    body: string,
    view_count: integer,
  )

  has_one :author, type: :people
  has_many :comments
end

class PersonPrimalizer < Primalize::JSONAPI[:people]
  attributes(
    name: string,
    email: string,
  )
end

class CommentPrimalizer < Primalize::JSONAPI[:comments]
  attributes(
    body: string,
    author_name: string,
  )
  alias comment object

  def author_name
    comment.author.name
  end
end

ActiveModel::Serializer.config.adapter = :json_api
ActiveModel::Serializer.config.key_transform = :underscore
ActiveModelSerializers.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new('/dev/null'))

class ArticleSerializer < ActiveModel::Serializer
  attributes :title, :body, :view_count

  belongs_to :author
  has_many :comments
end

class PersonSerializer < ActiveModel::Serializer
  attributes :name, :email
end

class CommentSerializer < ActiveModel::Serializer
  attributes :body, :author_name

  def author_name
    object.author.name
  end
end

people = Array.new(10) do |i|
  Person.new(
    id: i,
    name: FFaker::Name.name,
    email: FFaker::Internet.email,
  )
end
articles = Array.new(50) do |i|
  Article.new(
    id: i,
    title: 'Foo',
    body: 'Lorem ipsum dolor sit amet omg lol wtf bbq lmao rofl',
    view_count: 12,
    author: people.sample,
    comments: Array.new(rand(100)) do |comment_id|
      Comment.new(
        id: comment_id,
        body: 'lol this is a comment and i am writing it',
        author: people.sample,
      )
    end,
  )
end
article = articles.first

pp primalized = ArticlePrimalizer.new(articles, include: %i(author comments)).call.tap { |hash| hash[:included].sort_by! { |id:, type:, **| [type, id] } }
# pp ArticlePrimalizer.new(articles, include: %i(author comments)).call
pp ams = ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments).join(',')).as_json.tap { |hash| hash[:included].sort_by! { |id:, type:, **| [type, id] } }

p(
  single: Primalize::JSONAPI.serialize(articles: [article], include: %i(author comments)) == ActiveModelSerializers::SerializableResource.new([article], include: %i(author comments).join(',')).as_json,
  multi: primalized == ams,
)


require 'pry'
binding.pry

Benchmark.ips do |x|
  x.report 'single object to hash' do
    ArticlePrimalizer.new(article).call
  end

  x.report 'AMS single to hash' do
    ActiveModelSerializers::SerializableResource.new(article).as_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'single w/ associations to hash' do
    ArticlePrimalizer.new(article, include: %i(author comments)).call
  end

  x.report 'AMS single to hash' do
    ActiveModelSerializers::SerializableResource.new(article, include: %i(author comments)).as_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'multiple objects to hash' do
    ArticlePrimalizer.new(articles).call
  end

  x.report 'AMS single to hash' do
    ActiveModelSerializers::SerializableResource.new(articles).as_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'multiple w/ associations to hash' do
    Primalize::JSONAPI.serialize(articles: articles, include: %i(author comments))
  end

  x.report 'AMS multiple to hash' do
    ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments)).as_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'single object to string' do
    ArticlePrimalizer.new(article).to_json
  end

  x.report 'AMS single to string' do
    ActiveModelSerializers::SerializableResource.new(article).to_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'single w/ associations to string' do
    ArticlePrimalizer.new(article, include: %i(author comments)).to_json
  end

  x.report 'AMS single to string' do
    ActiveModelSerializers::SerializableResource.new(article, include: %i(author comments)).to_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'multiple objects to string' do
    ArticlePrimalizer.new(articles).to_json
  end

  x.report 'AMS single to string' do
    ActiveModelSerializers::SerializableResource.new(articles).to_json
  end

  x.compare!
end

Benchmark.ips do |x|
  x.report 'multiple w/ associations to string' do
    Primalize::JSONAPI.serialize(articles: articles, include: %i(author comments))
  end

  x.report 'AMS multiple to string' do
    ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments)).to_json
  end

  x.compare!
end
