module('objects', package.seeall)

function new_token_id(r, object)
  return r:increment(object .. ":next.id")
end

function token2id(r, object, token, makenew)
  local sha1hash = sha1(token) -- sha1hash(token)
  local id_key = object .. ":" .. sha1hash .. ":id"
  local id = r:get(id_key)
  if not id and makenew then
    id = new_token_id(r, object)
    local string_key = object .. ":" .. id .. ":string"
    r:set(string_key, token)
    if not r:set_preserve(id_key, id) then
      -- someone added the new token faster than us
      r:del(string_key, token)
      id = get_unique_id(r, object, token)
    end
  end
  return id
end

function id2token(r, object, id)
  local string_key = object .. ":" .. id .. ":string"
  return r:get(string_key)
end

function get_url_id(r, url, title)
  local url_id = token2id(r, "url", url, true)
  local obj_type_id = "url:" .. url_id
  local obj_title_id = obj_type_id .. ":title"
  if title and title ~= "" then
    r:set(obj_title_id, title)
  end
  return url_id, obj_type_id
end

function url_get_short(obj_id)
  return "u/" .. tostring(obj_id)
end

function link_to(obj)
  local t = {}
  local i,j,otype, oid = string.find(obj.type_id, "(%a+):([0-9]+)$")
  if not oid then oid = "_" end
  if otype == nil then otype = "?" end
  local attrs = "id=\"" .. otype .. "_" .. oid .. "\" onclick=\"return et(this);\" ";
  local tagtext = '<img src="/go.lua.d/images/tags.png" alt="[tags]" class="tagbtn"/>';
  if otype == "url" then
    if not obj.title or obj.title == "" then
      obj.title = obj.string
    end
    t = { "<a ", attrs, " href=\"?obj=", obj.type_id, "\">", tagtext, "</a> <a href=\"",
                                      url_get_short(oid), "\">", obj.title, "</a> | ", obj.string }
  elseif otype == "note" then
    t = { "<a ", attrs, " href=\"?obj=", obj.type_id, "\">", tagtext, "</a> <a href=\"note?type_id=", obj.type_id, "\">Note: ",
                             obj.title, "</a> | ", obj.string }
  elseif otype == "user" then
    t = { "<a ", attrs, " href=\"?obj=", obj.type_id, "\">", tagtext, "</a> User: ", obj.string }
  else
    t = { "<a ", attrs, " href=\"?obj=", obj.type_id, "\">", tagtext, "</a> ", obj.string }
  end
  return table.concat(t, "")
end

function get_object(r, type_id) 
  local o = {}
  if type_id then
    o.type_id = type_id
    o.title = r:get(type_id .. ":title")
    o.string = r:get(type_id .. ":string")
  end
  return o
end
