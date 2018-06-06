require 'primalize/jsonapi'
require 'grand_central/model'

class Model < GrandCentral::Model
  # Maybe we'll need something here?
end

class Movie < Model
  attributes(
    :id,
    :name,
    :release_year,
    :actors,
    :owner,
    :movie_type,
  )
end

class Actor < Model
  attributes :id, :name, :email
end

class MovieType < Model
  attributes :id, :name
end

class User < Model
  attributes :id, :name
end

class MovieSerializer < Primalize::JSONAPI[:movies]
  attributes name: string, release_year: optional(integer)

  has_many(:actors)
  has_one(:owner, type: :users)
  has_one(:movie_type, type: :movie_types)
end

class ActorSerializer < Primalize::JSONAPI[:actors]
  attributes name: string, email: string
end

class UserSerializer < Primalize::JSONAPI[:users]
  attributes name: string
end

class MovieTypeSerializer < Primalize::JSONAPI[:movie_types]
  attributes name: string
end

module Primalize
  RSpec.describe JSONAPI do
    it "has a version number" do
      expect(JSONAPI::VERSION).not_to be nil
    end

    describe 'serialization' do
      let(:movie) do
        Movie.new(
          id: 1,
          name: 'Back to the Future',
          release_year: 1985,
          actors: [
            Actor.new(id: 1, name: 'Michael J. Fox', email: 'michaeljfox@hollywood.com'),
            Actor.new(id: 2, name: 'Christopher Lloyd', email: 'docbrown@hollywood.com'),
          ],
          owner: User.new(
            id: 1,
            name: 'Jamie',
          ),
          movie_type: MovieType.new(
            id: 1,
            name: 'Science Fiction',
          ),
        )
      end

      let(:serialized_model) do
        { # ModelPrimalizer
          id: '1',
          type: 'movies',
          attributes: { # AttributePrimalizer
            name: 'Back to the Future',
            release_year: 1985,
          },
          relationships: {
            actors: {
              data: [
                { id: '1', type: 'actors' },
                { id: '2', type: 'actors' },
              ],
            },
            owner: { data: { id: '1', type: 'users' } },
            movie_type: { data: { id: '1', type: 'movie_types' } },
          },
        }
      end

      it 'serializes models' do
        expect(MovieSerializer.new(movie).call).to eq(data: [serialized_model])
      end

      it 'serializes models with metadata' do
        serializer = MovieSerializer.new(movie, meta: { total: 1 })

        expect(serializer.call).to eq(
          data: [serialized_model],
          meta: { total: 1 },
        )
      end

      it 'serializes included associations' do
        serializer = MovieSerializer.new(movie, include: %i(actors movie_type))
        result = serializer.call

        expect(result[:data]).to eq([serialized_model])
        expect(result[:included].count).to eq 3
        expect(result[:included]).to include(
          hash_including(
            id: '1',
            type: 'actors',
            attributes: {
              name: 'Michael J. Fox',
              email: 'michaeljfox@hollywood.com',
            },
          ),
          hash_including(
            id: '2',
            type: 'actors',
            attributes: {
              name: 'Christopher Lloyd',
              email: 'docbrown@hollywood.com',
            },
          ),
          hash_including(
            id: '1',
            type: 'movie_types',
            attributes: { name: 'Science Fiction' },
          ),
        )
      end

      it 'allows for nil has_one associations' do
        movie = self.movie.update(owner: nil)
        serializer = MovieSerializer.new(movie, include: %i(owner))
        result = serializer.call

        expect(result[:data]).to eq([
          serialized_model.merge(
            relationships: serialized_model[:relationships].merge(
              owner: nil,
            ),
          ),
        ])
      end
    end

    describe 'declaration' do
      let(:klass) { Class.new }
      let(:serializer_class) { JSONAPI[klass] }

      it 'sets the default primalizer' do
        expect(JSONAPI[klass]).to be serializer_class
      end

      it 'sets inherited class as default primalizer' do
        new_class = Class.new(serializer_class)

        expect(JSONAPI[klass]).to be new_class
      end
    end
  end
end
