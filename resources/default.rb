#
# Author:: Seth Chisamore <schisamo@chef.io>
# Cookbook:: chef_handler
# Resource:: default
#
# Copyright:: 2011-2017, Chef Software, Inc <legal@chef.io>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

property :class_name, String, name_property: true
property :source, String
property :arguments, [Array, String], default: []

# we have to set default for the supports attribute
# in initializer since it is a 'reserved' attribute name
def initialize(*args)
  super
  @supports = { report: true, exception: true }
end

# This action needs to find an rb file that presumably contains the indicated class in it and the
# load that file.  It then instantiates that class by name and registers it as a handler.
action :enable do
  class_name = new_resource.class_name
  new_resource.supports.each do |type, enable|
    next unless enable
    unregister_handler(type, class_name)
  end

  handler = nil

  require new_resource.source unless new_resource.source.nil?

  _, klass = get_class(class_name)
  handler = klass.send(:new, *collect_args(new_resource.arguments))

  new_resource.supports.each do |type, enable|
    next unless enable
    register_handler(type, handler)
  end
end

action :disable do
  new_resource.supports.each_key do |type|
    unregister_handler(type, new_resource.class_name)
  end
end

action_class.class_eval do
  def collect_args(resource_args = [])
    if resource_args.is_a? Array
      resource_args
    else
      [resource_args]
    end
  end

  # Registers a handler in Chef::Config.
  #
  # @param handler_type [Symbol] such as :report or :exception.
  # @param handler [Chef::Handler] handler to register.
  def register_handler(handler_type, handler)
    Chef::Log.info("Enabling #{handler.class.name} as a #{handler_type} handler.")
    Chef::Config.send("#{handler_type}_handlers") << handler
  end

  # Removes all handlers that match the given class name in Chef::Config.
  #
  # @param handler_type [Symbol] such as :report or :exception.
  # @param class_full_name [String] such as 'Chef::Handler::ErrorReport'.
  def unregister_handler(handler_type, class_full_name)
    Chef::Log.info("Disabling #{class_full_name} as a #{handler_type} handler.")
    Chef::Config.send("#{handler_type}_handlers").delete_if { |v| v.class.name == class_full_name }
  end

  # Walks down the namespace heirarchy to return the class object for the given class name.
  # If the class is not available, NameError is thrown.
  #
  # @param class_full_name [String] full class name such as 'Chef::Handler::Foo' or 'MyHandler'.
  # @return [Array] parent class and child class.
  def get_class(class_full_name)
    ancestors = class_full_name.split('::')
    class_name = ancestors.pop

    # We need to search the ancestors only for the first/uppermost namespace of the class, so we
    # need to enable the #const_get inherit paramenter only when we are searching in Kernel scope
    # (see COOK-4117).
    parent = ancestors.inject(Kernel) { |scope, const_name| scope.const_get(const_name, scope === Kernel) }
    child = parent.const_get(class_name, parent === Kernel)
    [parent, child]
  end
end
