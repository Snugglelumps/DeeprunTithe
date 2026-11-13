# Deeprun Tithe

A guild tithe for WoW Forever. When you sell gray items at a vendor, it works out what you owe the guild. You pay it at the guild bank.

## For members

Install it and play. What you owe shows at the bottom of your bags.

1. Sell your grays at any vendor. Your tithe goes up when you close the vendor.
2. Open the guild bank. A bar sits under the tabs.
3. Click **Pay Tithe** to pay exactly what you owe, or **Pay Custom Tithe** to pay a different amount.

Only gold paid with those two buttons counts. The bank's own Deposit button isn't recorded and won't lower what you owe.

Trade goods count too. Drop them in the guild bank and they're worth twice their vendor price off your tithe.

Grays you keep, delete or give away aren't income, so they owe nothing.

## For guilds

The addon has no settings. It reads your guild's rate, trade goods value and starting level from a code in Guild Info, which looks like this:

```
[[cj0wLjA1O3Q9...]]
```

Paste it anywhere in the Guild Information box and every member picks it up automatically. The code is made by Deeprun Ledger, the treasurer's addon, with `/drl hash`. Without a code, the tithe is 5%, trade goods count double, and tithes start at level 20.

Payments are sent to Deeprun Ledger over guild addon messages, and it checks them against the guild bank's money log.

Anyone in your guild can read the code, and anyone who can edit Guild Info can change the rates, so keep that rank trusted. The transaction IDs stop casual and hand-typed fakes. They won't stop someone determined.
