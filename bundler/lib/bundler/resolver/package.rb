# frozen_string_literal: true

module Bundler
  class Resolver
    class Package
      attr_reader :name, :platforms, :locked_version, :dependency
      attr_accessor :depth

      def initialize(name, platforms = [], locked_version = nil, unlock = false, dependency = nil, root: false)
        @name = name
        @platforms = platforms
        @locked_version = locked_version
        @unlock = unlock
        @dependency = dependency
        @root = root
      end

      def to_s
        @name.delete("\0")
      end

      def root?
        @root
      end

      def meta?
        @name.end_with?("\0")
      end

      def ==(other)
        return false unless other.is_a?(Package)

        @name == other.name && root? == other.root?
      end

      def hash
        [@name, root?].hash
      end

      def unlock?
        @unlock
      end

      def force_ruby_platform?
        @dependency&.force_ruby_platform
      end

      def prerelease_specified?
        @dependency&.prerelease?
      end

      def current_platform?
        @dependency&.current_platform?
      end
    end
  end
end
