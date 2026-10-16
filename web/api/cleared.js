const { ethers } = require("ethers");

const RPC = process.env.RPC || "https://rpc.testnet.arc.network";
const TREASURY = process.env.TREASURY || "0x7064D005274140D5d960931A84d2e04ab1D15E94";
const USDC = "0x3600000000000000000000000000000000000000";

const TREASURY_ABI = [
  "function pay(address vendor, uint256 amount, bytes32 invoiceHash)",
  "function vendorCap(address) view returns (uint256)",
  "function invoicePaid(bytes32) view returns (bool)",
  "error NotOwner()", "error NotAgent()", "error ContractPaused()", "error ZeroAmount()",
  "error VendorNotApproved()", "error OverVendorCap()", "error OverDailyCap()",
  "error InvoiceAlreadyPaid()", "error TransferFailed()",
];
const USDC_ABI = ["function balanceOf(address) view returns (uint256)"];

const VENDORS = {
  acme: { name: "Acme Supplies Ltd", seed: "cleared-demo-vendor-acme" },
  northgate: { name: "Northgate Shell Holdings", seed: "cleared-demo-vendor-northgate" },
  stranger: { name: "Unregistered Vendor", seed: "cleared-attacker" },
};
for (const v of Object.values(VENDORS)) v.address = new ethers.Wallet(ethers.id(v.seed)).address;

// Fictional test list. Swap in a real sanctions snapshot for production.
const SANCTIONED = ["northgate shell holdings"];
const usd = (u) => (Number(u) / 1e6).toFixed(2);

module.exports = async (req, res) => {
  try {
    const provider = new ethers.JsonRpcProvider(RPC, 5042002, {
      staticNetwork: ethers.Network.from(5042002),
      pollingInterval: 500,
    });
    const treasury = new ethers.Contract(TREASURY, TREASURY_ABI, provider);
    const usdc = new ethers.Contract(USDC, USDC_ABI, provider);

    if (req.method === "GET") {
      const balance = await usdc.balanceOf(TREASURY);
      const vendors = await Promise.all(
        Object.entries(VENDORS).map(async ([id, v]) => ({
          id, name: v.name, address: v.address,
          cap: (await treasury.vendorCap(v.address)).toString(),
        }))
      );
      return res.status(200).json({ treasury: TREASURY, balance: balance.toString(), vendors });
    }
    if (req.method !== "POST") return res.status(405).json({ error: "method not allowed" });
    if (!process.env.AGENT_KEY) return res.status(500).json({ error: "agent key not configured" });

    const { vendor, amount, invoice, mode } = req.body || {};
    const v = VENDORS[vendor];
    const amt = Number(amount);
    if (!v) return res.status(400).json({ error: "unknown vendor" });
    if (!(amt > 0 && amt <= 100)) return res.status(400).json({ error: "amount must be between 0 and 100" });
    if (!invoice || String(invoice).length > 40) return res.status(400).json({ error: "invoice number required, 40 chars max" });

    const units = BigInt(Math.round(amt * 1e6));
    const hash = ethers.id(String(invoice));
    const signer = new ethers.Wallet(process.env.AGENT_KEY, provider);
    const agent = treasury.connect(signer);

    if (mode !== "bypass") {
      if (SANCTIONED.includes(v.name.toLowerCase())) {
        return res.status(200).json({ decision: "REFUSED", layer: "policy engine", reason: "SANCTIONS_MATCH: vendor is on the screening list. No funds moved." });
      }
      if (await treasury.invoicePaid(hash)) {
        return res.status(200).json({ decision: "REFUSED", layer: "policy engine", reason: "DUPLICATE_INVOICE: this invoice number was already paid." });
      }
      const cap = await treasury.vendorCap(v.address);
      if (cap === 0n) {
        return res.status(200).json({ decision: "REFUSED", layer: "policy engine", reason: "VENDOR_NOT_APPROVED: first payment needs owner approval." });
      }
      if (units > cap) {
        return res.status(200).json({ decision: "REFUSED", layer: "policy engine", reason: "OVER_VENDOR_CAP: limit for this vendor is " + usd(cap) + " USDC." });
      }
      const tx = await agent.pay(v.address, units, hash);
      await tx.wait();
      return res.status(200).json({ decision: "PAID", layer: "policy engine + contract", reason: "All checks passed. Settled in USDC on Arc.", tx: tx.hash });
    }

    let wouldFail = null;
    try { await agent.pay.staticCall(v.address, units, hash); }
    catch (e) { wouldFail = (e.revert && e.revert.name) || "UNKNOWN"; }
    const tx = await agent.pay(v.address, units, hash, { gasLimit: 300000n });
    try {
      await tx.wait();
      return res.status(200).json({ decision: "PAID", layer: "contract (policy skipped)", reason: "Contract rules allowed it.", tx: tx.hash });
    } catch (e) {
      return res.status(200).json({ decision: "REVERTED", layer: "treasury contract", reason: (wouldFail || "UNKNOWN") + ": the contract refused onchain.", tx: tx.hash });
    }
  } catch (e) {
    return res.status(500).json({ error: e.shortMessage || e.message });
  }
};
