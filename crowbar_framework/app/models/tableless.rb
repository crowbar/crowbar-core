#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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

class Tableless
  include ActiveModel::Model
  extend ActiveModel::Callbacks

  define_model_callbacks :save, :create, :update

  attr_accessor :new_record

  def initialize(attrs = nil)
    self.new_record = true
    super
  end

  def save
    valid? && persist
  end

  def persisted?
    if new_record
      false
    else
      true
    end
  end

  def new_record?
    if new_record
      true
    else
      false
    end
  end

  protected

  def persist
    run_callbacks :save do
      persist!
    end
  end

  def persist!
    if new_record?
      create
    else
      update
    end
  end

  def create
    run_callbacks :create do
      create!
    end
  end

  def create!
  end

  def update
    run_callbacks :update do
      update!
    end
  end

  def update!
  end
end
