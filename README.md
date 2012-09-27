ADDRESSIVE - makes uris agressive!
=====================

Idea behind this: encapsulate the whole uri generating stuff in a simple object graph. This approach yields some nice effects:

  - the whole uri generating stuff is accessible via one object with just one interface
  -  ... which is totally ideal for dependency injection
  -  ... or mocking
  - all uris are generated with simple string templates
  -  ... so your uri generating scheme is perfectly serializeable
  -  ... and follows open standards
  -  ... who said decoupling?

Examples
-----------------

    routing = Addressive.node do
      uri '/foo'
    end
    routing.uri.to_s #=> '/foo'

Okay, this was easy.


