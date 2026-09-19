# frozen_string_literal: true

require "test_helper"
require "database/setup"
require "active_support/core_ext/object/with"

class ActiveStorage::ParallelTestingTest < ActiveSupport::TestCase
  setup do
    @original_configurations = Rails.configuration.active_storage.service_configurations
    @original_services = ActiveStorage::Blob.services
    @original_service = ActiveStorage::Blob.service
  end

  teardown do
    Rails.configuration.active_storage.service_configurations = @original_configurations
    ActiveStorage::Blob.services = @original_services
    ActiveStorage::Blob.service = @original_service
  end

  test "every Disk service gets the worker's root" do
    local_root = @original_services.fetch(:local).root
    local_public_root = @original_services.fetch(:local_public).root

    run_after_fork_hooks(worker: 7)

    assert_equal "#{local_root}_7", ActiveStorage::Blob.services.fetch(:local).root
    assert_equal "#{local_public_root}_7", ActiveStorage::Blob.services.fetch(:local_public).root
  end

  test "the default service is also replaced" do
    run_after_fork_hooks(worker: 7)

    assert_same ActiveStorage::Blob.services.fetch(:local), ActiveStorage::Blob.service
  end

  test "Disk services inside a Mirror service get the worker's root" do
    original_mirror = @original_services.fetch(:mirror)

    run_after_fork_hooks(worker: 7)

    mirror = ActiveStorage::Blob.services.fetch(:mirror)
    assert_equal "#{original_mirror.primary.root}_7", mirror.primary.root
    assert_equal original_mirror.mirrors.map { |service| "#{service.root}_7" }, mirror.mirrors.map(&:root)
  end

  test "Disk services configured with a lowercase service name get the worker's root" do
    Rails.configuration.active_storage.service_configurations = @original_configurations.merge("lower" => { "service" => "disk", "root" => "/dummy/lower" })

    run_after_fork_hooks(worker: 7)

    assert_equal "/dummy/lower_7", ActiveStorage::Blob.services.fetch(:lower).root
  end

  test "non-Disk services are left alone" do
    remote = { "service" => "S3", "bucket" => "bucket", "root" => "not a directory" }
    Rails.configuration.active_storage.service_configurations = @original_configurations.merge("remote" => remote)

    run_after_fork_hooks(worker: 7)

    assert_equal remote, Rails.configuration.active_storage.service_configurations[:remote]
  end

  test "uploads land in the worker's root" do
    run_after_fork_hooks(worker: 7)

    blob = create_blob(data: "worker 7")
    path = blob.service.send(:path_for, blob.key)

    assert path.start_with?("#{@original_service.root}_7"), "#{path} is not under the worker's root"
    assert_equal "worker 7", File.read(path)
  ensure
    blob&.purge
  end

  private
    def run_after_fork_hooks(worker:)
      ActiveSupport.with(parallelize_test_databases: false) do
        ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(worker) }
      end
    end
end
