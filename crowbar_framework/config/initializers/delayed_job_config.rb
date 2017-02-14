#
# Copyright 2016, SUSE LINUX GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Delayed
  class Worker
    def handle_failed_job_with_logging(job, error)
      handle_failed_job_without_logging(job, error)
      Rails.logger.error("Error processing job ID #{job.id}: #{error.message} "\
        "#{error.backtrace.join("\n")}")
    end
    alias_method_chain :handle_failed_job, :logging
  end
end

Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.delay_jobs = !Rails.env.test?
Delayed::Worker.raise_signal_exceptions = :term
Delayed::Worker.max_attempts = 1
log_file = if Rails.env.production?
  File.join(ENV["CROWBAR_LOG_DIR"], "background_jobs.log")
else
  File.join(Rails.root, "log", "background_jobs.log")
end
Delayed::Worker.logger = Logger.new(log_file)
