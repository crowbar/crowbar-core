require "chef/mixin/language_include_recipe"

class Chef
  module Mixin
    module LanguageIncludeRecipe
      def include_recipe_smartly(*list_of_recipes)
		# Iterate over the dependcies and  find if either have changed
        # if it has changed include the recipe
		#    "horizon::server" => [
		#        ['glance','api','bind_port'],
		#        ['horizon']
		#    ]
        # - break immediately on first changed dependency
        # - if dependency list is empty, include recipe
        # - log accordingly
        list_of_recipes.each do |recipe|
          included = false
          dependancylist = BarclampLibrary::Barclamp::DependsOn.get(recipe)
          dependancylist.each do |dependency|
            next unless BarclampLibrary::Barclamp::Config.changes_to_apply?(dependency)
            Chef::Log.info("[smart] including recipe : #{recipe}")
            Chef::Log.debug("[smart] due to change in: #{dependency}")
            include_recipe recipe
            included = true
            break
          end.empty? and begin
            include_recipe recipe
            Chef::Log.info("[smart] including recipe without depencies: #{recipe}")
          end # each
          Chef::Log.info("[smart] recipe excluded: #{recipe}") unless included
        end # each
      end # def include_recipe_smartly
    end
  end
end
