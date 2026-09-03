// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

/// @notice Minimal interface for Uniswap Permit2 SignatureTransfer, vendored so the
///         protocol compiles against a single solc version. Only the batch
///         permitTransferFrom surface StockPack uses is declared.
///         Canonical deployment (verified on Robinhood Chain): 0x000000000022D473030F116dDEE9F6B43aC78BA3
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitBatchTransferFrom {
        TokenPermissions[] permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    function permitTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
