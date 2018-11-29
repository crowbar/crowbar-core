require "chef/mixin/language_include_recipe"

class Chef
  module Mixin
    module LanguageIncludeRecipe
      def include_recipe_smartly(*list_of_recipes)
        list_of_recipes.each do |recipe|
          included = false
          BarclampLibrary::Barclamp::DependsOn.get(recipe).each do |dependency|
            next unless BarclampLibrary::Barclamp::Config.changes_to_apply?(dependency)
            Chef::Log.info("[smart] including recipe: #{recipe}")
            Chef::Log.debug("[smart] due to change in: #{dependency}")
            include_recipe recipe
            included = true
            break
          end # each
          Chef::Log.info("[smart] recipe excluded: #{recipe}") unless included
        end # each
      end # def include_recipe_smartly
    end
  end
end
