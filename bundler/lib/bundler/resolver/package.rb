# frozen_string_literal: true

module Bundler
  class Resolver
    class Package
      attr_reader :name, :platforms, :locked_version

      def initialize(name, platforms = [], locked_version = nil, unlock = false, force_ruby_platform = false, prerelease_specified = false, root: false)
        @name = name
        @platforms = platforms
        @locked_version = locked_version
        @unlock = unlock
        @force_ruby_platform = force_ruby_platform
        @prerelease_specified = prerelease_specified
        @root = root
      end

      def to_s
        @name
      end

      def root?
        @root
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
        @force_ruby_platform
      end

      def prerelease_specified?
        @prerelease_specified
      end
    end
  end
end
