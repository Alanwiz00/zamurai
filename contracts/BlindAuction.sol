// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {FHE, externalEuint64, euint64, eaddress, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ConfidentialERC20} from "./ConfidentialERC20.sol"; // Uncomment and ensure the file exists at the specified path

contract BlindAuction is SepoliaConfig, ReentrancyGuard {
    // ========== State Variables ==========
    address public immutable beneficiary;

    /// @notice Confidenctial Payment Token
    ConfidentialERC20 public confidentialERC20;
    IERC721 public immutable nftContract;
    uint256 public immutable tokenId;
    uint256 public immutable auctionEndTime;

    // Encrypted auction state
    euint64 private highestBid;
    eaddress private winningAddress;

    // Decrypted winner (set after auction ends)
    address public winnerAddress;
    bool public isNftClaimed;

    // Bid tracking
    mapping(address => euint64) private bids;
    mapping(address => bool) private hasWithdrawn;
    uint256 private _decryptionRequestId;

    // ========== Events ==========
    event BidPlaced(address indexed bidder);
    event AuctionEnded(address indexed winner);
    event NFTClaimed(address indexed winner);

    // ========== Modifiers ==========
    modifier onlyDuringAuction() {
        require(block.timestamp < auctionEndTime, "Auction ended");
        _;
    }

    modifier onlyAfterAuction() {
        require(block.timestamp >= auctionEndTime, "Auction not ended");
        _;
    }

    modifier onlyWinner() {
        require(msg.sender == winnerAddress, "Not winner");
        _;
    }

    // ========== Constructor ==========
    constructor(address _nftContract, uint256 _tokenId, uint256 _durationMinutes, address _confidentialERC20) {
        // Validate NFT contract
        require(IERC165(_nftContract).supportsInterface(type(IERC721).interfaceId), "Not ERC721");
        require(IERC721(_nftContract).ownerOf(_tokenId) == msg.sender, "Caller must own NFT");

        beneficiary = msg.sender;
        nftContract = IERC721(_nftContract);
        tokenId = _tokenId;
        auctionEndTime = block.timestamp + (_durationMinutes * 60);

        // Transfer NFT to this contract
        nftContract.safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    // ========== Core Functions ==========
    function bid(externalEuint64 encryptedBid, bytes calldata bidProof) external onlyDuringAuction nonReentrant {
        // Verify and decrypt bid
        euint64 bidAmount = FHE.fromExternal(encryptedBid, bidProof);

        // Update bid tracking
        bids[msg.sender] = bidAmount;

        // Update highest bid if needed
        if (FHE.isInitialized(highestBid)) {
            ebool isHigher = FHE.gt(bidAmount, highestBid);
            highestBid = FHE.select(isHigher, bidAmount, highestBid);
            winningAddress = FHE.select(isHigher, FHE.asEaddress(msg.sender), winningAddress);
        } else {
            highestBid = bidAmount;
            winningAddress = FHE.asEaddress(msg.sender);
        }

        emit BidPlaced(msg.sender);
    }

    function decryptWinner() external onlyAfterAuction {
        require(winnerAddress == address(0), "Winner already revealed");

        bytes32[] memory ciphertexts = new bytes32[](1);
        ciphertexts[0] = FHE.toBytes32(winningAddress);
        _decryptionRequestId = FHE.requestDecryption(ciphertexts, this.resolveWinnerCallback.selector);
    }

    function claimNFT() external onlyWinner nonReentrant {
        require(!isNftClaimed, "NFT already claimed");

        isNftClaimed = true;
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTClaimed(msg.sender);
    }

    function withdraw(bytes calldata encryptedAmount, bytes calldata inputProof) external nonReentrant {
        require(!hasWithdrawn[msg.sender], "Already withdrawn");
        require(winnerAddress != address(0), "Winner not revealed");
        require(msg.sender != winnerAddress, "Winner can't withdraw");
        require(FHE.isInitialized(bids[msg.sender]), "No bid to withdraw");

        // Clear bid to prevent reentrancy
        euint64 amount = TFHE.asEuint64(encryptedAmount, inputProof);
        ebool isCorrectAmount = FHE.eq(amount, bids[msg.sender]);
        require(isCorrectAmount, "Incorrect amount");

        confidentialERC20.transfer(msg.sender, encryptedAmount, inputProof);

        bids[msg.sender] = FHE.asEuint64(0);
        hasWithdrawn[msg.sender] = true;
    }

    // ========== FHE Callback ==========
    function resolveWinnerCallback(uint256 requestId, address decryptedWinner, bytes[] memory signatures) external {
        require(requestId == _decryptionRequestId, "Invalid request");
        FHE.checkSignatures(requestId, signatures);

        winnerAddress = decryptedWinner;
        emit AuctionEnded(decryptedWinner);
    }

    // ========== Views ==========
    function getAuctionStatus() external view returns (bool isEnded, address winner) {
        return (block.timestamp >= auctionEndTime, winnerAddress);
    }
}
