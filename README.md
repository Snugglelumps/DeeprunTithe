# Deeprun Tithe

A guild tithe for WoW Forever. It adds up the gray items you loot, works out what you owe the guild, and fills in the payment mail for you.

## For members

Install it and play. A small bar sits next to the Inbox and Send Mail tabs on the mailbox.

1. Open a mailbox.
2. Attach any trade goods you want to give. They count for 3x their vendor price. Gray items don't count, so vendor those and pay with the gold.
3. Click the bar. It fills in the mail and the gold.
4. Click Send.

Hover over the bar to see what you owe and what's attached. If it says **Not set up**, your guild hasn't added its code yet. Your debt is still being tracked, so nothing is lost.

The guild covers your postage: each tithe you send takes 30 copper off what you'd owe next.

## For guilds

The addon has no settings. It reads your guild's rate, starting level and treasurers from a code in Guild Info, which looks like this:

```
[[cj0wLjA1O3Q9...]]
```

Paste it anywhere in the Guild Information box and every member picks it up automatically. The code is made by Deeprun Ledger, the treasurer's addon, with `/drl hash`.

The first treasurer in the code receives the mail. All treasurers are exempt from tithes.

Anyone in your guild can read the code, and anyone who can edit Guild Info can change where tithes go, so keep that rank trusted. The transaction IDs stop casual and hand-typed fakes. They won't stop someone determined.
