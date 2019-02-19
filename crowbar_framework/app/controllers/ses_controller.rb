#
# Copyright 2019, SUSE
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

class SesController < ApplicationController
  # Render the settings page, where currently stored settings are visible
  # and yaml file with configuration can be uploaded.
  def settings
    @ses_settings = SES.load
  end

  def upload
    data = upload_params[:file].read
    begin
      config = YAML.safe_load(data)
    rescue YAML::SyntaxError => e
      return render json: { error: "YAML parsing failed: #{e.problem}" }, status: :unprocessable_entity
    end
    if validate(config)
      SES.save(config)
      render json: config, status: :ok
    else
      render json: { error: "validation error" }, status: :unprocessable_entity
    end
  end

  def delete
    SES.save nil
    redirect_to ses_settings_path
  end

  private

  def validate(config)
    # TODO: validate structure
    true
  end

  def upload_params
    params.require(:sesconfig).permit(:file)
  end
end
