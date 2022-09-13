# frozen_string_literal: true

require_relative "../vendor/pub_grub/lib/pub_grub/basic_package_source"
require_relative "version"

module Bundler
  class Resolver
    class PackageSource < PubGrub::BasicPackageSource
      attr_reader :root_dependencies

      def initialize(resolver, root_dependencies, gem_version_promoter)
        @resolver = resolver
        @root_dependencies = to_dependency_hash(root_dependencies)
        @gem_version_promoter = gem_version_promoter

        super()
      end

      def dependencies_for(package, version)
        to_dependency_hash(version.spec_group.dependencies)
      end

      def all_versions_for(package)
        all_versions = @resolver.all_versions_for(package)

        @gem_version_promoter.sort_versions(package, all_versions).reverse
      end

      def parse_dependency(package, dependency)
        range_ruby = requirement_to_range(dependency)

        Bundler::PubGrub::VersionConstraint.new(package, :range => range_ruby)
      end

      def sort_versions_by_preferred(package, sorted_versions)
        @gem_version_promoter.sort_versions(package, sorted_versions).reverse
      end

      def incompatibilities_for(package, version)
        package_deps = @cached_dependencies[package]
        sorted_versions = @sorted_versions[package]
        package_deps[version].map do |dep_package, dep_constraint_name|
          low = high = sorted_versions.index(version)

          # find version low such that all >= low share the same dep
          while low > 0 &&
                package_deps[sorted_versions[low - 1]][dep_package] == dep_constraint_name
            low -= 1
          end
          low =
            if low == 0
              nil
            else
              sorted_versions[low]
            end

          # find version high such that all < high share the same dep
          while high < sorted_versions.length &&
                package_deps[sorted_versions[high]][dep_package] == dep_constraint_name
            high += 1
          end
          high =
            if high == sorted_versions.length
              nil
            else
              sorted_versions[high]
            end

          range = PubGrub::VersionRange.new(:min => low, :max => high, :include_min => true)

          self_constraint = PubGrub::VersionConstraint.new(package, :range => range)

          dep_constraint = parse_dependency(dep_package, dep_constraint_name)
          if !dep_constraint
            # falsey indicates this dependency was invalid
            cause = PubGrub::Incompatibility::InvalidDependency.new(dep_package, dep_constraint_name)
            return [PubGrub::Incompatibility.new([PubGrub::Term.new(self_constraint, true)], :cause => cause)]
          elsif !dep_constraint.is_a?(PubGrub::VersionConstraint)
            # Upgrade range/union to VersionConstraint
            dep_constraint = PubGrub::VersionConstraint.new(dep_package, :range => dep_constraint)
          end

          PubGrub::Incompatibility.new([PubGrub::Term.new(self_constraint, true), PubGrub::Term.new(dep_constraint, false)], :cause => :dependency)
        end
      end

      private

      def requirement_to_range(requirement)
        ranges = requirement.requirements.map do |(op, rubygems_ver)|
          ver = Version.new(rubygems_ver)

          case op
          when "~>"
            name = "~> #{ver}"
            bump = Version.new(rubygems_ver.bump.to_s + ".A")
            PubGrub::VersionRange.new(:name => name, :min => ver, :max => bump, :include_min => true)
          when ">"
            PubGrub::VersionRange.new(:min => ver)
          when ">="
            PubGrub::VersionRange.new(:min => ver, :include_min => true)
          when "<"
            PubGrub::VersionRange.new(:max => ver)
          when "<="
            PubGrub::VersionRange.new(:max => ver, :include_max => true)
          when "="
            PubGrub::VersionRange.new(:min => ver, :max => ver, :include_min => true, :include_max => true)
          when "!="
            PubGrub::VersionRange.new(:min => ver, :max => ver, :include_min => true, :include_max => true).invert
          else
            raise "bad version specifier: #{op}"
          end
        end

        ranges.inject(&:intersect)
      end

      def to_dependency_hash(dependencies)
        dependencies.inject({}) do |deps, dep|
          package = @resolver.packages[dep.name]

          current_req = deps[package]
          if current_req
            deps[package] = Gem::Requirement.new(current_req.as_list.concat(dep.requirement.as_list).uniq)
          else
            deps[package] = dep.requirement
          end

          deps
        end
      end
    end
  end
end
