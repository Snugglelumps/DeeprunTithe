-- Deeprun Tithe: the account ID, so the ledgers can tie alts together
-- One ID per WoW account, made once and never changed. Every time a ledger sends RDY,
-- we answer ACC|<id>. That's one tiny message about every 4 minutes. The character's name
-- isn't in it, because the server stamps the sender.
-- The ID isn't secret. Anyone listening could copy it, and the worst they can do is
-- put their own character on someone else's account.
--
-- Saved for the account (see DeeprunTithe.toc):
--   deeprun_client_id  10 hex digits with a dash after the 4th, like a3f9-c01e42

local addon_name, shared = ...


-- 10 hex digits from any text, shown 4-6 with a dash: a3f9-c01e42
local function short_hash(text)
    local hash = 0
    for character_number = 1, #text do
        hash = (hash * 31 + string.byte(text, character_number)) % 1099511627776
    end

    -- Printed as two halves, because string.format can't safely print a number this big in hex
    local high_part = math.floor(hash / 1048576)
    local low_part = hash % 1048576
    local hash_text = string.format("%05x%05x", high_part, low_part)

    return string.sub(hash_text, 1, 4) .. "-" .. string.sub(hash_text, 5, 10)
end


-- Answers each RDY
function shared.sendAccountID()
    C_ChatInfo.SendAddonMessage(shared.prefix, shared.accMessage(deeprun_client_id), "GUILD")
end


local account_frame = CreateFrame("Frame")
account_frame:RegisterEvent("PLAYER_LOGIN")

account_frame:SetScript("OnEvent", function()
    -- The first character to log in with this addon names the account. Its name and the time
    -- only make the ID unique. Nothing reads them back out.
    if deeprun_client_id == nil then
        deeprun_client_id = short_hash(UnitName("player") .. GetServerTime())
    end
end)
