# frozen_string_literal: true

module Bundler
  class Resolver
    require_relative "vendored_pub_grub"
    require_relative "resolver/base"
    require_relative "resolver/package"
    require_relative "resolver/version"

    include GemHelpers

    def initialize(source_requirements, base, gem_version_promoter, additional_base_requirements)
      @source_requirements = source_requirements
      @base = Resolver::Base.new(base, additional_base_requirements)
      @results_for = {}
      @gem_version_promoter = gem_version_promoter
    end

    def start(requirements, packages, exclude_specs: [])
      exclude_specs.each do |spec|
        remove_from_candidates(spec)
      end

      root = Resolver::Package.new(name_for_explicit_dependency_source, :root => true)

      packages[:root] = root

      root_dependencies = to_dependency_hash(requirements, packages)

      root_version = Resolver::Version.new(0)

      cached_versions = Hash.new do |h,k|
        h[k] = if k.root?
          [root_version]
        else
          all_versions_for(k)
        end
      end

      @sorted_versions = Hash.new {|h,k| h[k] = cached_versions[k].sort }

      root_dependencies = verify_gemfile_dependencies_are_found!(root_dependencies)

      @cached_dependencies = Hash.new do |dependencies, package|
        dependencies[package] = if package.root?
          { root_version => root_dependencies }
        else
          Hash.new do |versions, version|
            versions[version] = to_dependency_hash(version.spec_group.dependencies, packages)
          end
        end
      end

      logger = Bundler::UI::Shell.new
      logger.level = debug? ? "debug" : "warn"
      solver = PubGrub::VersionSolver.new(:source => self, :root => root, :logger => logger)
      Bundler.ui.info "Resolving dependencies...\n", debug?
      result = solver.solve
      result.map {|package, version| version.to_specs(package.force_ruby_platform?) unless package.root? }.compact.flatten.uniq
    rescue PubGrub::SolveFailure => e
      incompatibility = e.incompatibility

      names_to_unlock = []

      while incompatibility.conflict?
        incompatibility = incompatibility.cause.incompatibility
        incompatibility.terms.each do |term|
          name = term.package.name
          names_to_unlock << name if base_requirements[name]
        end
      end

      if names_to_unlock.any?
        @base.unlock_deps(names_to_unlock)
        retry
      end

      raise SolveFailure.new(e.message)
    end

    def parse_dependency(package, dependency)
      range = if repository_for(package).is_a?(Source::Gemspec)
        PubGrub::VersionRange.any
      else
        requirement_to_range(dependency)
      end

      PubGrub::VersionConstraint.new(package, :range => range)
    end

    def versions_for(package, range=VersionRange.any)
      versions = range.select_versions(@sorted_versions[package])

      if versions.size > 1
        sort_versions(package, versions)
      else
        versions
      end
    end

    def incompatibilities_for(package, version)
      package_deps = @cached_dependencies[package]
      sorted_versions = @sorted_versions[package]
      package_deps[version].map do |dep_package, dep_constraint|
        unless dep_constraint
          # falsey indicates this dependency was invalid
          cause = PubGrub::Incompatibility::InvalidDependency.new(dep_package, dep_constraint.constraint_string)
          return [PubGrub::Incompatibility.new([PubGrub::Term.new(self_constraint, true)], :cause => cause)]
        end

        low = high = sorted_versions.index(version)

        # find version low such that all >= low share the same dep
        while low > 0 && package_deps[sorted_versions[low - 1]][dep_package] == dep_constraint
          low -= 1
        end
        low =
          if low == 0
            nil
          else
            sorted_versions[low]
          end

        # find version high such that all < high share the same dep
        while high < sorted_versions.length && package_deps[sorted_versions[high]][dep_package] == dep_constraint
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

        dep_term = PubGrub::Term.new(dep_constraint, false)

        custom_explanation = if dep_package.name.end_with?("\0") && package.root?
          "current #{dep_package.name.strip} version is #{dep_constraint.constraint_string}"
        end

        PubGrub::Incompatibility.new([PubGrub::Term.new(self_constraint, true), dep_term], :cause => :dependency, :custom_explanation => custom_explanation)
      end
    end

    def debug?
      ENV["BUNDLER_DEBUG_RESOLVER"] ||
        ENV["BUNDLER_DEBUG_RESOLVER_TREE"] ||
        ENV["DEBUG_RESOLVER"] ||
        ENV["DEBUG_RESOLVER_TREE"] ||
        false
    end

    def all_versions_for(package)
      name = package.name
      results = @base[name] + results_for(name)
      locked_requirement = base_requirements[name]
      results = results.select {|spec| requirement_satisfied_by?(locked_requirement, spec) } if locked_requirement

      versions = results.group_by(&:version).reduce([]) do |groups, (version, specs)|
        platform_specs = package.platforms.flat_map {|platform| select_best_platform_match(specs, platform) }
        next groups if platform_specs.empty?

        ruby_specs = select_best_platform_match(specs, Gem::Platform::RUBY)
        groups << Resolver::Version.new(version, :specs => ruby_specs) if ruby_specs.any?

        next groups if platform_specs == ruby_specs

        groups << Resolver::Version.new(version, :specs => platform_specs)

        groups
      end

      sort_versions(package, versions)
    end

    def sort_versions(package, versions)
      @gem_version_promoter.sort_versions(package, versions).reverse
    end

    def index_for(name)
      source_for(name).specs
    end

    def repository_for(package)
      source_for(package.name)
    end

    def source_for(name)
      @source_requirements[name] || @source_requirements[:default]
    end

    def results_for(name)
      @results_for[name] ||= index_for(name).search(name)
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue StandardError
      "Gemfile"
    end

    def requirement_satisfied_by?(requirement, spec)
      requirement.matches_spec?(spec) || spec.source.is_a?(Source::Gemspec)
    end

    private

    def base_requirements
      @base.base_requirements
    end

    def remove_from_candidates(spec)
      @base.delete(spec)

      @results_for.keys.each do |name|
        next unless name == spec.name

        @results_for[name].reject {|s| s.version == spec.version }
      end
    end

    def verify_gemfile_dependencies_are_found!(dependencies)
      dependencies.map do |dep_package, dep_constraint|
        name = dep_package.name

        next [dep_package, dep_constraint] if name == "bundler"
        next if dep_package.platforms.empty?

        next [dep_package, dep_constraint] unless versions_for(dep_package, dep_constraint.range).empty?
        next unless dep_package.current_platform?

        raise GemNotFound, gem_not_found_message(dep_package, dep_constraint)
      end.compact.to_h
    end

    def gem_not_found_message(package, requirement)
      name = package.name
      source = source_for(name)
      specs = source.specs.search(name).sort_by {|s| [s.version, s.platform.to_s] }
      matching_part = name
      requirement_label = SharedHelpers.pretty_dependency(package.dependency)
      cache_message = begin
                          " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                        rescue GemfileNotFound
                          nil
                        end
      specs_matching_requirement = specs.select {| spec| package.dependency.matches_spec?(spec) }

      if specs_matching_requirement.any?
        specs = specs_matching_requirement
        matching_part = requirement_label
        platforms = package.platforms
        platform_label = platforms.size == 1 ? "platform '#{platforms.first}" : "platforms '#{platforms.join("', '")}"
        requirement_label = "#{requirement_label}' with #{platform_label}"
      end

      message = String.new("Could not find gem '#{requirement_label}' in #{source}#{cache_message}.\n")

      if specs.any?
        message << "\nThe source contains the following gems matching '#{matching_part}':\n"
        message << specs.map {|s| "  * #{s.full_name}" }.join("\n")
      end

      message
    end

    def requirement_to_range(requirement)
      ranges = requirement.requirements.map do |(op, rubygems_ver)|
        ver = Resolver::Version.new(rubygems_ver)

        case op
        when "~>"
          name = "~> #{ver}"
          bump = Resolver::Version.new(rubygems_ver.bump.to_s + ".A")
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

    def to_dependency_hash(dependencies, packages)
      dependencies.inject({}) do |deps, dep|
        package = packages[dep.name]

        current_req = deps[package]
        new_req = parse_dependency(package, dep.requirement)

        deps[package] = if current_req
          current_req.intersect(new_req)
        else
          new_req
        end

        deps
      end
    end
  end
end
