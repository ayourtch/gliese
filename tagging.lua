module('tagging', package.seeall)

local tempkey_expiry = 5

function get_url_obj_type_id(url)
  local url_id = myutil.token2id(redis, "url", url, true)
  local obj_type_id = "url:" .. url_id
  return obj_type_id
end

-- Extended sets - xsets
-- zset which gets synced to set for scores > 0

function get_xset_ids(xset)
  return xset .. ":zset", xset .. ":set", xset .. ":lock", xset .. ":busy"
end

function xset_add_use(xset, member_id)
  local xset_zset_id, xset_set_id, xset_lock_id, xset_busy_id = get_xset_ids(xset)
  if 1 <= tonumber(redis:zset_increment_by(xset_zset_id, 1, member_id)) then
    redis:set_add(xset_set_id, member_id)
    if 0 >= tonumber(redis:zset_score(xset_zset_id, member_id)) then
      redis:set_remove(xset_set_id, member_id)
    end
  end
end


function xset_del_use(xset, member_id)
  local xset_zset_id, xset_set_id, xset_lock_id, xset_busy_id = get_xset_ids(xset)
  if 0 >= tonumber(redis:zset_increment_by(xset_zset_id, -1, member_id)) then
    redis:set_remove(xset_set_id, member_id)
    if 1 <= tonumber(redis:zset_score(xset_zset_id, member_id)) then
      redis:set_add(xset_set_id, member_id)
    end
  end
end

function tag_search_add(tagname)
  for i=1,string.len(tagname)-2 do
    local triplet = string.sub(tagname, i, i+2)
    xset_add_use("tagsearch:triplet:" .. triplet, tagname)
  end
end

function tag_search_del(tagname)
  for i=1,string.len(tagname)-2 do
    local triplet = string.sub(tagname, i, i+2)
    xset_del_use("tagsearch:triplet:" .. triplet, tagname)
  end
end


-- return the list of tags that may match the given substring
function tag_search(user_id, str)
  local sets = {}
  local my_result_key = "result:tagsearch:user:".. user_id
  local result = {}
  for i=1,string.len(str)-2 do
    sets[#sets + 1] = "tagsearch:triplet:" .. string.sub(str, i, i+2) .. ":set"
  end
  if #sets > 0 then
    redis:set_intersection_store(my_result_key, unpack(sets))
    redis:expire(my_result_key, 500)
    -- TODO: take only N top items. Sort by frequency...
    -- local result = redis:set_members(my_result_key)
    result = redis:sort(my_result_key, { get = '#' }) or {}
  end
  return result
end


function tag_attach(user_id, obj_type_id, tagname)
  local tag_key = "tagging:tag:" .. tagname .. ":user:" .. user_id
  local global_tag_key = "tagging:tag:" .. tagname .. ":global"
  local global_doctags_key = "tagging:global:" .. obj_type_id .. ":tags"
  -- tagclouds
  local global_tagcloud_key = "tagging:cloud:global"
  local tagcloud_key = "tagging:cloud:user:" .. user_id
  -- global tag maintenance
  xset_add_use(global_tag_key, obj_type_id)
  xset_add_use(global_doctags_key, tagname)
  xset_add_use(global_tagcloud_key, tagname)
  -- search only "human" flags
  if(string.sub(tagname, 1, 1) ~= "[") then
    tag_search_add(tagname)
  end
  -- per-user tag maintenance
  redis:set_add(tag_key, obj_type_id)
  xset_add_use(tagcloud_key, tagname)
end

function tag_detach(user_id, obj_type_id, tagname)
  local tag_key = "tagging:tag:" .. tagname .. ":user:" .. user_id
  local global_tag_key = "tagging:tag:" .. tagname .. ":global"
  local global_doctags_key = "tagging:global:" .. obj_type_id .. ":tags"
  -- tagclouds
  local global_tagcloud_key = "tagging:cloud:global"
  local tagcloud_key = "tagging:cloud:user:" .. user_id
  -- global tag maintenance
  xset_del_use(global_tag_key, obj_type_id)
  xset_del_use(global_doctags_key, tagname)
  xset_del_use(global_tagcloud_key, tagname)
  -- search only "human" flags
  if(string.sub(tagname, 1, 1) ~= "[") then
    tag_search_del(tagname)
  end
  -- per-user tag maintenance
  redis:set_remove(tag_key, obj_type_id)
  xset_del_use(tagcloud_key, tagname)
  if redis:set_cardinality(tag_key) == 0 then
    redis:expire(tag_key, tempkey_expiry)
    if redis:set_cardinality(tag_key) > 0 then
      -- someone added while we had the expiry set. cancel it.
      redis:set_add(tag_key, "null:0")
      redis:set_remove(tag_key, "null:0")
    end
  end
end

function tags_get_global(obj_type_id)
  local global_taglist_key = "tagging:global:" .. obj_type_id .. ":tags:set"
  return redis:set_members(global_taglist_key)
end

function tags_get(user_id, obj_type_id)
  local user_taglist_key = "tagging:user:" .. user_id .. ":" .. obj_type_id .. ":tags"
  return redis:set_members(user_taglist_key)
end

function tags_get_editable(user_id, obj_type_id)
  local usertags = tags_get(user_id, obj_type_id)
  local result = {}
  local result_excluded = {}
  local taghash = {}
  if usertags then
    for i,v in ipairs(usertags) do
      taghash[v] = true
    end
    for i,v in ipairs(usertags) do
      local pos = string.find(v, "/")
      if pos then
        local v1 = string.sub(v, 1, pos-1)
        local v2 = string.sub(v, pos)
        taghash[v1] = nil
        taghash[v2] = nil
      end
    end
    
    for v,yes in pairs(taghash) do
      local firstchar = string.sub(v, 1, 1)
      if firstchar == '[' then
        -- do not add these
        result_excluded[#result_excluded+1] = v
      else
        result[#result+1] = v
      end
    end
  else   
    result = nil
  end
  return result, result_excluded
end

function tags_set(user_id, obj_type_id, supplied_tags, options)
  local user_taglist_key = "tagging:user:" .. user_id .. ":" .. obj_type_id .. ":tags"
  local user_taglist_key_temp = user_taglist_key .. ":temp"
  local old_tags = redis:set_members(user_taglist_key) or {}
  local new_tags = {} -- we will create this from supplied_tags
  local tag_count = 0
  local copy_systags = (not options) or (not options.override_systags)
  local add_only = options and options.add_only

  -- transfer the "undeletable" tags ("[something]"), as well as all the tags in case of add-only mode
  for i,v in ipairs(old_tags) do
    if add_only then
      new_tags[#new_tags + 1] = v
    elseif copy_systags then
      if (string.sub(v, 1, 1) == "[") then
        new_tags[#new_tags + 1] = v
      end
    end 
  end

  if options and options.norecurse then
    -- need to set the tags verbatim, without the @-recursion
    for i,v in ipairs(supplied_tags) do
        new_tags[#new_tags + 1] = v
      local pos = string.find(v, "/")
      if pos then
        local v1 = string.sub(v, 1, pos-1)
        local v2 = string.sub(v, pos)
        table.insert(new_tags, v1)
        table.insert(new_tags, v2)
      end
    end
  else
    -- check if we need to inject users' tags (@target) too
    for i,v in ipairs(supplied_tags) do
      if string.sub(v, 1, 1) == "@" then
        local their_id = myusers.username2id(redis, string.sub(v, 2, -1))
        if their_id then
          if their_id == user_id then
            new_tags[#new_tags + 1] = v 
          else
            tags_set(their_id, obj_type_id, { v }, { norecurse = true, add_only = true }) 
          end
        end
      else
        new_tags[#new_tags + 1] = v 
        local pos = string.find(v, "/")
        if pos then
          local v1 = string.sub(v, 1, pos-1)
          local v2 = string.sub(v, pos)
          table.insert(new_tags, v1)
          table.insert(new_tags, v2)
        end
      end
    end
  end

  -- prepare the new tagset
  redis:delete(user_taglist_key_temp)
  for i,v in ipairs(new_tags) do
    redis:set_add(user_taglist_key_temp, v)
    tag_count = tag_count + 1
  end
  -- will need to iterate and do something with them
  local tags_to_add = redis:set_diff(user_taglist_key_temp, user_taglist_key)
  local tags_to_del = redis:set_diff(user_taglist_key, user_taglist_key_temp)
  for i,v in ipairs(tags_to_add) do
    tag_attach(user_id, obj_type_id, v)
  end
  for i,v in ipairs(tags_to_del) do
    tag_detach(user_id, obj_type_id, v)
  end
  
  if tag_count > 0 then
    redis:rename(user_taglist_key_temp, user_taglist_key)
  else
    redis:delete(user_taglist_key)
  end
  
end

function tags_search(zone, tags, user_id)
  local setnametrailer
  local result = {}
  if zone == "user" then  
    setnametrailer = ":user:" .. user_id
  elseif zone == "global" then
    setnametrailer = ":global:set"
  else
    return {}
  end

  if tags[1] then
    local names = {}
    local my_result_key = "result:user:".. user_id
    local r
    for i,v in ipairs(tags) do
      names[i] = "tagging:tag:" .. v .. setnametrailer
    end
    redis:set_intersection_store(my_result_key, unpack(names))
    redis:expire(my_result_key, 500)
    -- TODO: take only N top items. Sort by frequency...
    -- local result = redis:set_members(my_result_key)
    r = redis:sort(my_result_key, { get = '# GET *:string GET *:title' }) or {}
    for i = 1, #r, 3 do
      table.insert(result, { type_id = r[i], string = r[i+1], title = r[i+2] })
    end
  end
  return result 
end
