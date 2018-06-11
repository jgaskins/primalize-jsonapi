require 'benchmark/ips'
$:.unshift 'lib'
$:.unshift '../active_model_serializers/lib'
require 'active_model_serializers'
require 'primalize/jsonapi'
require 'grand_central/model'
require 'ffaker'
require 'securerandom'

class Model < GrandCentral::Model
  def read_attribute_for_serialization attr
    public_send attr
  end
end

class Article < Model
  attributes :id, :title, :body, :view_count, :author, :comments

  def author_id(*args)
    author&.id
  end

  def comment_ids
    comments.map(&:id)
  end
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

require 'fast_jsonapi'
module Netflix
  class ArticleSerializer
    include FastJsonapi::ObjectSerializer

    set_type :articles

    attributes :title, :body, :view_count

    belongs_to :author
    has_many :comments
  end

  class PersonSerializer
    include FastJsonapi::ObjectSerializer

    set_type :people

    attributes :name, :email
  end
  AuthorSerializer = PersonSerializer

  class CommentSerializer
    include FastJsonapi::ObjectSerializer

    set_type :comments

    attributes :body
    attribute :author_name do |comment|
      comment.author.name
    end
  end
end

require 'primalize'
# require 'oj'
module Response
  class ArticlePrimalizer < Primalize::Single
    attributes(
      id: integer,
      title: string,
      body: string,
      view_count: integer,
      author_id: integer,
      comment_ids: array(integer),
    )
    alias article object

    def author_id
      article.author.id
    end

    def comment_ids
      article.comments.map(&:id)
    end
  end

  class PersonPrimalizer < Primalize::Single
    attributes(
      id: integer,
      name: string,
      email: string,
    )
  end

  class CommentPrimalizer < Primalize::Single
    attributes(
      id: integer,
      body: string,
      author_name: string,
    )
    alias comment object

    def author_name
      comment.author.name
    end
  end

  class Response < Primalize::Many
    # def to_json
    #   Oj.dump call, mode: :json
    # end
  end

  class ArticlesResponse < Response
    attributes(
      articles: enumerable(ArticlePrimalizer),
    )
  end

  class ArticlesResponseWithAssociations < ArticlesResponse
    attributes(
      authors: enumerable(PersonPrimalizer),
      comments: enumerable(CommentPrimalizer),
    )

    def initialize articles:, authors: articles.flat_map(&:author).uniq, comments: articles.flat_map(&:comments)
      super(
        articles: articles,
        authors: authors,
        comments: comments,
      )
    end
  end

  class ArticleResponse < Primalize::Many
    attributes(
      article: ArticlePrimalizer,
    )
  end

  class ArticleResponseWithAssociations < ArticleResponse
    attributes(
      author: PersonPrimalizer,
      comments: enumerable(CommentPrimalizer),
    )

    def initialize article:, author: article.author, comments: article.comments
      super(
        article: article,
        author: author,
        comments: comments,
      )
    end
  end
end

people = Array.new(10) do |i|
  Person.new(
    id: i,
    name: FFaker::Name.name,
    email: FFaker::Internet.email,
  )
end
comment_id = 0
articles = Array.new(25) do |i|
  Article.new(
    id: i,
    title: 'Foo',
    body: 'Lorem ipsum dolor sit amet omg lol wtf bbq lmao rofl',
    view_count: 12,
    author: people.sample,
    comments: Array.new(SecureRandom.random_number(0..10)) do
      Comment.new(
        id: comment_id += 1,
        body: 'lol this is a comment and i am writing it',
        author: people.sample,
      )
    end,
  )
end
article = articles.first

primalized = ArticlePrimalizer.new(articles, include: %i(author comments)).call.tap { |hash| hash[:included].sort_by! { |id:, type:, **| [type, id] } }
ams = ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments).join(',')).as_json.tap { |hash| hash[:included].sort_by! { |id:, type:, **| [type, id] } }

pp(
  single_no_associations: pp(Primalize::JSONAPI.serialize(articles: article)) == pp(ActiveModelSerializers::SerializableResource.new([article]).as_json),
  multi_no_associations: Primalize::JSONAPI.serialize(articles: articles) == ActiveModelSerializers::SerializableResource.new(articles).as_json,
  single_with_associations: Primalize::JSONAPI.serialize(
    articles: article,
    include: %i(author comments),
  ) == ActiveModelSerializers::SerializableResource.new(
    [article],
    include: %i(author comments),
  ).as_json,
  multi_with_associations: primalized == ams,
)

pp Response::ArticlesResponse.new(articles: articles).call
require 'pry'
binding.pry

puts 'SINGLE OBJECT, NO ASSOCIATIONS, TO HASH'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(article).call
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(article).as_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(article).as_json
  end

  x.report 'Primalize::Many' do
    Response::ArticleResponse.new(article: article).call
  end

  x.compare!
end

puts 'SINGLE OBJECT, W/ ASSOCIATIONS, TO HASH'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(article, include: %i(author comments)).call
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(article, include: %i(author comments)).as_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(article, include: %w(author comments)).as_json
  end

  x.report 'Primalize::Many' do
    Response::ArticleResponseWithAssociations.new(article: article).call
  end

  x.compare!
end

puts 'MULTIPLE OBJECTS, NO ASSOCIATIONS, TO HASH'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(articles).call
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(articles).as_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(articles).as_json
  end

  x.report 'Primalize::Many' do
    Response::ArticlesResponse.new(articles: articles).call
  end

  x.compare!
end

puts 'MULTIPLE OBJECTS, W/ ASSOCIATIONS, TO HASH'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    Primalize::JSONAPI.serialize(articles: articles, include: %i(author comments))
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments)).as_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(articles, include: %i(author comments)).as_json
  end

  x.report 'Primalize::Many' do
    Response::ArticlesResponseWithAssociations.new(articles: articles).call
  end

  x.compare!
end

puts 'SINGLE OBJECT, NO ASSOCIATIONS, TO STRING'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(article).to_json
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(article).to_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(article).to_json
  end

  x.report 'Primalize::Many' do
    Response::ArticleResponse.new(article: article).to_json
  end

  x.compare!
end

puts 'SINGLE OBJECT, W/ ASSOCIATIONS, TO STRING'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(article, include: %i(author comments)).to_json
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(article, include: %i(author comments)).to_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(article, include: %i(author comments)).to_json
  end

  x.report 'Primalize::Many' do
    Response::ArticleResponseWithAssociations.new(article: article).to_json
  end

  x.compare!
end

puts 'MULTIPLE OBJECTS, NO ASSOCIATIONS, TO STRING'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    ArticlePrimalizer.new(articles).to_json
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(articles).to_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(articles).to_json
  end

  x.report 'Primalize::Many' do
    Response::ArticlesResponse.new(articles: articles).to_json
  end

  x.compare!
end

puts 'MULTIPLE OBJECTS, W/ ASSOCIATIONS, TO STRING'
Benchmark.ips do |x|
  x.report 'Primalize::JSONAPI' do
    Primalize::JSONAPI.serialize(articles: articles, include: %i(author comments)).to_json
  end

  x.report 'AMS' do
    ActiveModelSerializers::SerializableResource.new(articles, include: %i(author comments)).to_json
  end

  x.report 'FastJsonapi' do
    Netflix::ArticleSerializer.new(articles, include: %w(author comments)).to_json
  end

  x.report 'Primalize::Many' do
    Response::ArticlesResponseWithAssociations.new(articles: articles).to_json
  end

  x.compare!
end
