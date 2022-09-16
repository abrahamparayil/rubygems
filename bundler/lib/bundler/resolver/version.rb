# frozen_string_literal: true

require_relative "spec_group"

module Bundler
  class Resolver
    class Version
      include Comparable

      attr_reader :spec_group, :rubygems_version, :platforms

      def initialize(version, specs: [])
        @spec_group = Resolver::SpecGroup.new(specs) if specs.any?
        @platforms = specs.map(&:platform).sort_by(&:to_s).uniq
        @rubygems_version = Gem::Version.new(version)
        @ruby_only = @platforms == [Gem::Platform::RUBY]
      end

      def to_specs(force_ruby_platform)
        @spec_group.to_specs(force_ruby_platform)
      end

      def prerelease?
        @rubygems_version.prerelease?
      end

      def segments
        @rubygems_version.segments
      end

      def sort_obj
        [@rubygems_version, @ruby_only ? -1 : 1]
      end

      def <=>(other)
        return @rubygems_version <=> other.rubygems_version if platforms.empty? || other.platforms.empty?

        sort_obj <=> other.sort_obj
      end

      def ==(other)
        return unless other.is_a?(Resolver::Version)
        return @rubygems_version == other.rubygems_version if platforms.empty? || other.platforms.empty?

        sort_obj == other.sort_obj
      end

      def eql?(other)
        return unless other.is_a?(Resolver::Version)
        return @rubygems_version.eql?(other.rubygems_version) if platforms.empty? || other.platforms.empty?

        sort_obj.eql?(other.sort_obj)
      end

      def hash
        sort_obj.hash
      end

      def to_s
        return @rubygems_version.to_s if @platforms.empty? || @ruby_only

        "#{@rubygems_version} (#{@platforms.join(", ")})"
      end
    end
  end
end
