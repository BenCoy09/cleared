// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

contract Treasury {
    IERC20 public immutable usdc;
    address public immutable owner;
    address public agent;
    uint256 public dailyCap;
    bool public paused;

    mapping(address => uint256) public vendorCap;
    mapping(bytes32 => bool) public invoicePaid;
    mapping(uint256 => uint256) public spentOnDay;

    event VendorSet(address indexed vendor, uint256 maxPerPayment);
    event AgentSet(address indexed agent);
    event DailyCapSet(uint256 cap);
    event PausedSet(bool paused);
    event Paid(address indexed vendor, uint256 amount, bytes32 indexed invoiceHash);

    error NotOwner();
    error NotAgent();
    error ContractPaused();
    error ZeroAmount();
    error VendorNotApproved();
    error OverVendorCap();
    error OverDailyCap();
    error InvoiceAlreadyPaid();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address usdc_, address agent_, uint256 dailyCap_) {
        usdc = IERC20(usdc_);
        owner = msg.sender;
        agent = agent_;
        dailyCap = dailyCap_;
    }

    function setVendor(address vendor, uint256 maxPerPayment) external onlyOwner {
        vendorCap[vendor] = maxPerPayment;
        emit VendorSet(vendor, maxPerPayment);
    }

    function setAgent(address newAgent) external onlyOwner {
        agent = newAgent;
        emit AgentSet(newAgent);
    }

    function setDailyCap(uint256 cap) external onlyOwner {
        dailyCap = cap;
        emit DailyCapSet(cap);
    }

    function setPaused(bool value) external onlyOwner {
        paused = value;
        emit PausedSet(value);
    }

    function sweep(address to, uint256 amount) external onlyOwner {
        _send(to, amount);
    }

    function pay(address vendor, uint256 amount, bytes32 invoiceHash) external {
        if (msg.sender != agent) revert NotAgent();
        if (paused) revert ContractPaused();
        if (amount == 0) revert ZeroAmount();

        uint256 cap = vendorCap[vendor];
        if (cap == 0) revert VendorNotApproved();
        if (amount > cap) revert OverVendorCap();
        if (invoicePaid[invoiceHash]) revert InvoiceAlreadyPaid();

        uint256 day = block.timestamp / 1 days;
        uint256 newTotal = spentOnDay[day] + amount;
        if (newTotal > dailyCap) revert OverDailyCap();

        invoicePaid[invoiceHash] = true;
        spentOnDay[day] = newTotal;

        _send(vendor, amount);
        emit Paid(vendor, amount, invoiceHash);
    }

    function _send(address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            address(usdc).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
