module('myusers', package.seeall)
require 'objects'

function username2id(redis, username)
  return objects.token2id(redis, "user", username, false)
end

function username2id_create(redis, username)
  return objects.token2id(redis, "user", username, true)
end
