# frozen_string_literal: true

module Bundler::PubGrub
  class Package

    attr_reader :name
    attr_accessor :depth

    def initialize(name)
      @name = name
    end

    def inspect
      "#<#{self.class} #{name.inspect}>"
    end

    def <=>(other)
      name <=> other.name
    end

    ROOT = Package.new(:root)
    ROOT_VERSION = 0

    def self.root
      root = ROOT
      root.depth = 0
      root
    end

    def self.root_version
      ROOT_VERSION
    end

    def to_s
      name.to_s
    end

    def root?
      name == :root
    end
  end
end
