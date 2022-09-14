# frozen_string_literal: true

module Bundler
  class Resolver
    class Package
      attr_reader :name, :platforms, :locked_version

      def initialize(name, platforms, locked_version, force_ruby_platform = false, prerelease_specified = false)
        @name = name
        @platforms = platforms
        @locked_version = locked_version
        @force_ruby_platform = force_ruby_platform
        @prerelease_specified = prerelease_specified
      end

      def ==(other)
        @name == other.name
      end

      def hash
        @name.hash
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
