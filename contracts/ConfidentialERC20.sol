// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity >=0.8.13 <0.9.0;

import "fhevm/lib/TFHE.sol";

contract ConfidentialERC20 {
    // ========== State Variables ==========
    string public constant name = "Naraggara";
    string public constant symbol = "NARA";
    uint8 public constant decimals = 18;
    using TFHE for euint64;
    euint64 private totalSupply = TFHE.asEuint64(100000000 * 10 ** decimals); // 100 million tokens with 18 decimals
    euint64 private burnable;
    address private immutable contractOwner;

    mapping(address => euint64) private balances;
    mapping(address => mapping(address => euint64)) private allowances;

    // ========== Events ==========
    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);

    // ========== Modifiers ==========
    modifier onlyOwner() {
        require(msg.sender == contractOwner, "Unauthorized");
        _;
    }

    modifier onlySignedPublicKey(bytes32 publicKey, bytes calldata signature) {
        // Implement signature verification logic here
        _;
    }

    // ========== Constructor ==========
    constructor() {
        contractOwner = msg.sender;
        balances[contractOwner] = totalSupply;
    }

    // ========== Core Functions ==========
    function transfer(address to, einput inputHandle, bytes calldata inputProof) public {
        euint64 amount = TFHE.asEuint64(inputHandle, inputProof);
        _transfer(msg.sender, to, amount);
    }

    function approve(address spender, einput inputHandle, bytes calldata inputProof) public {
        allowances[msg.sender][spender] = TFHE.asEuint64(inputHandle, inputProof);
        emit Approval(msg.sender, spender);
    }

    function transferFrom(address from, address to, einput inputHandle, bytes calldata inputProof) public {
        euint64 amount = TFHE.asEuint64(inputHandle, inputProof);
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
    }

    function transferEncrypted(address to, euint64 amount) public {
        _transfer(msg.sender, to, amount);
    }

    // ========== Internal Functions ==========
    function _transfer(address from, address to, euint64 amount) internal {
        ebool canTransfer = TFHE.le(amount, balances[from]);

        balances[from] = TFHE.select(canTransfer, TFHE.sub(balances[from], amount), balances[from]);

        balances[to] = TFHE.select(canTransfer, TFHE.add(balances[to], amount), balances[to]);

        require(TFHE.isSenderAllowed(canTransfer), "Insufficient balance");
        emit Transfer(from, to);
    }

    // Returns the balance of the caller under their public FHE key.
    function balanceOf(
        bytes32 publicKey,
        bytes calldata signature
    ) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
        return abi.encodePacked(euint64.unwrap(balances[msg.sender]));
    }

    function _spendAllowance(address owner, address spender, euint64 amount) internal {
        euint64 currentAllowance = allowances[owner][spender];
        require(TFHE.isSenderAllowed(TFHE.le(amount, currentAllowance)), "Insufficient allowance");
        allowances[owner][spender] = TFHE.sub(currentAllowance, amount);
    }
}
