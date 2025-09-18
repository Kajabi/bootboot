# frozen_string_literal: true

module Bootboot
  class GemfileNextAutoSync < Bundler::Plugin::API
    def setup
      check_bundler_version
      opt_in
    end

    private

    def check_bundler_version
      self.class.hook("before-install-all") do
        next if Bundler::VERSION >= "2.1.0" || !GEMFILE_NEXT_LOCK.exist?

        Bundler.ui.warn(<<-EOM.gsub(/\s+/, " "))
          Bootboot requires Bundler >= 2.1.0 for full unlock strategy support
          (conservative, patch, minor, strict). You are running #{Bundler::VERSION}.

          Update Bundler to 2.1.0+ to use all Bootboot features.
        EOM
      end
    end

    def opt_in
      self.class.hook("before-install-all") do
        @previous_lock = Bundler.default_lockfile.read
      end

      self.class.hook("after-install-all") do
        current_definition = Bundler.definition

        next if !GEMFILE_NEXT_LOCK.exist? ||
          nothing_changed?(current_definition) ||
          ENV[Bootboot.env_next] ||
          ENV[Bootboot.env_previous]

        update!(current_definition)
      end
    end

    def nothing_changed?(current_definition)
      current_definition.to_lock == @previous_lock
    end

    def update!(current_definition)
      env = which_env
      lock = which_lock

      Bundler.ui.confirm("Updating the #{lock}")
      ENV[env] = "1"
      ENV["BOOTBOOT_UPDATING_ALTERNATE_LOCKFILE"] = "1"

      # Reconstruct unlock hash to properly support conservative updates
      unlock = current_definition.instance_variable_get(:@unlock)
      gems_to_unlock = current_definition.instance_variable_get(:@gems_to_unlock) || []

      # If this was a conservative/restricted update, construct proper unlock hash
      if unlock[:conservative] || unlock[:patch] || unlock[:minor] || unlock[:strict]
        # For conservative updates, only unlock the specific requested gems
        constructed_unlock = {
          gems: gems_to_unlock,
          sources: false,
          dependencies: false
        }
        # Preserve other flags that Definition.build might need
        preserved_flags = unlock.select { |k, v| [:ruby, :conservative, :patch, :minor, :strict, :major, :pre].include?(k) }
        constructed_unlock.merge!(preserved_flags)
      else
        # For non-restrictive updates, use original unlock hash
        constructed_unlock = unlock
      end

      definition = Bundler::Definition.build(GEMFILE, lock, constructed_unlock)
      definition.resolve_remotely!
      definition.lock(lock)
    ensure
      ENV.delete(env)
      ENV.delete("BOOTBOOT_UPDATING_ALTERNATE_LOCKFILE")
    end

    def which_env
      if Bundler.default_lockfile.to_s =~ /_next\.lock/
        Bootboot.env_previous
      else
        Bootboot.env_next
      end
    end

    def which_lock
      if Bundler.default_lockfile.to_s =~ /_next\.lock/
        GEMFILE_LOCK
      else
        GEMFILE_NEXT_LOCK
      end
    end
  end
end
