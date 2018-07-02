require 'primalize/jsonapi/version'
require 'primalize/single'
require 'primalize/many'

module Primalize
  module JSONAPI
    @serializer_map = {}

    def self.serialize(include: [], meta: nil, **attrs)
      type, models = attrs.first

      self[type].new(models, include: include, meta: meta).call
    end

    def self.[] key
      @serializer_map[key] ||= Class.new(Serializer) do
        define_singleton_method :inherited do |klass|
          super klass

          JSONAPI.module_exec do
            @serializer_map[key] = klass
          end

          %i(
            AttributesSerializer
            RelationshipsSerializer
            MetadataSerializer
          ).each do |serializer|
            klass.const_set serializer, Class.new(Serializer.const_get(serializer))
          end

          klass.const_set :HasOne, Class.new(Serializer::HasOne) {
            attributes data: klass::MetadataSerializer
          }
          klass.const_set :HasOneOptional, Class.new(Serializer::HasOneOptional) {
            attributes data: optional(klass::MetadataSerializer)
          }
          klass.const_set :HasMany, Class.new(Serializer::HasMany) {
            attributes data: enumerable(klass::MetadataSerializer)
          }

          klass.const_set :ModelSerializer, Class.new(Serializer::ModelSerializer) {
            attributes(
              attributes: primalize(klass::AttributesSerializer),
              relationships: primalize(klass::RelationshipsSerializer),
            )

            define_method :attributes do
              klass::AttributesSerializer.new(object).call
            end

            define_method :relationships do
              attrs = klass::RelationshipsSerializer.attributes.each_with_object({}) do |(attr, _), hash|
                hash[attr] = { data: object.send(attr) }
              end

              klass::RelationshipsSerializer.new(attrs).call
            end
          }
          klass.const_set :DataSerializer, Class.new(Serializer::DataSerializer) {
            attributes(
              data: enumerable(klass::ModelSerializer),
            )
          }
          klass::MetadataSerializer.type = key
          klass::ModelSerializer.type = key

          def klass.method_added method_name
            klass = self
            self::AttributesSerializer.define_method method_name do |*args|
              klass.new(object).send(method_name, *args)
            end
          end
        end
      end
    end

    class Serializer
      include Single::Type

      class << self
        extend Forwardable
        delegate %i(string integer number array optional any object enum) => Single

        attr_writer :association_type_map

        def association_type_map
          @association_type_map ||= {}
        end
      end

      def self.attributes **attrs
        self::AttributesSerializer.attributes **attrs
      end

      def self.has_many association, type: association
        association_type_map[association] = type

        self::RelationshipsSerializer.attributes(
          association => DeferredAssociation.new(
            type: type,
            association_type: :HasMany,
          )
        )
      end

      def self.has_one association, type: association, optional: true
        association_type_map[association] = type

        self::RelationshipsSerializer.attributes(
          association => DeferredAssociation.new(
            type: type,
            association_type: optional ? :HasOneOptional : :HasOne,
          )
        )
      end

      class DeferredAssociation
        def initialize type:, association_type:
          @type = type
          @association_type = association_type
        end

        def new(*args)
          Primalize::JSONAPI[@type].const_get(@association_type).new(*args)
        end
      end

      attr_reader :object

      def initialize object, include: [], meta: nil
        @object = object
        @include = include
        @meta = meta
      end

      def call
        objects = Array(@object).uniq
        result = self.class::DataSerializer
          .new(data: objects)
          .call

        result.merge!(meta: @meta) if @meta

        if Array(@include).any?
          result.merge!(included: @include.flat_map { |assoc|
            objects
              .map { |obj| obj.send(assoc) }
              .uniq
              .flat_map { |value|
                JSONAPI[self.class.association_type_map[assoc]]
                  .new(value)
                  .call[:data]
              }
          })
        end

        result
      end

      class AttributesSerializer < Single
      end

      class RelationshipsSerializer < Many
      end

      class MetadataSerializer < Single
        attributes(
          id: string(&:to_s),
          type: string,
        )

        def type
          self.class.type.to_s
        end

        class << self
          attr_accessor :type
        end

        def self.inspect
          "MetadataSerializer(#{type.inspect})"
        end
      end

      class ModelSerializer < MetadataSerializer
      end

      class DataSerializer < Many
      end

      class HasMany < Many
      end

      class HasOne < Many
      end

      class HasOneOptional < Many
      end
    end
  end
end
