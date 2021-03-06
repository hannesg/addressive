# -*- encoding : utf-8 -*-
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the Affero GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#    (c) 2011 - 2012 by Hannes Georg
#

module Addressive; module Graph::BuildsURIs

  # Adds one or more uri specs for a given name.
  def uri(name_or_uri,*args)
    if name_or_uri.kind_of? Symbol
      name = name_or_uri
    else
      name = DEFAULT_ACTION
      args.unshift( name_or_uri )
    end
    specs = node.uri_spec(name)
    options = {}
    if args.size > 1 && args.last.kind_of?(Hash)
      options = args.pop
    end
    specs << spec_factory_with_options(options).convert(*args)
    return specs
  end


  def spec_factory_with_options(overrides={})
    return spec_factory.derive( defaults.merge(overrides) )
  end

  # Sets a default value for an option.
  def default(name, value)
    defaults[name] = value
  end

end; end