# Caching middleware with parallel requests is broken.
# I am monkey patching it here until the pull request gets merged
# https://github.com/lostisland/faraday_middleware/pull/121

module FaradayMiddleware
  class Caching < Faraday::Middleware
    def cache_on_complete(env)
      key = cache_key(env)
      if cached_response = cache.read(key)
        finalize_response(cached_response, env)
      else
        response = @app.call(env)

        # response.status is nil at this point, any checks need to be done inside on_complete block
        response.on_complete do
          if CACHEABLE_STATUS_CODES.include?(response.status)
            cache.write(key, response)
          end
        end

        response
      end
    end
  end
end
