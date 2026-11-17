// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/BTCLayer2BridgeERC20.sol";
import "../src/BTCLayer2BridgeERC721.sol";
import "../src/ERC20TokenWrapped.sol";
import "../src/ERC721TokenWrapped.sol";

/// @notice Local unit tests for Track B hypotheses (no fork needed).
/// @dev These confirm or deny secondary hypotheses. None of them is a
///      draftable finding on its own; see the hypotheses log for verdicts.
contract TrackBUnitTest is Test {
    BTCLayer2BridgeERC20 erc20;
    BTCLayer2BridgeERC721 erc721;
    address bridge = address(this);
    address user = address(0xBEEF);

    function setUp() public {
        erc20 = new BTCLayer2BridgeERC20();
        erc20.initialize(address(this), bridge);
        erc721 = new BTCLayer2BridgeERC721();
        erc721.initialize(address(this), bridge);
    }

    /// H-12: abi.encodePacked(name, symbol, ...) collides for ("AB","C") vs ("A","BC").
    /// The second registration is blocked with "The current token already exists".
    function test_encodePackedCollision_BlocksSecondRegistration() public {
        address t1 = erc20.addERC20TokenWrapped("AB", "C", 8, 1000);
        assertTrue(t1 != address(0));
        vm.expectRevert("The current token already exists");
        erc20.addERC20TokenWrapped("A", "BC", 8, 1000);
    }

    /// H-12b: same collision shape for ERC721 (name, symbol, baseURI).
    function test_encodePackedCollisionERC721_BlocksSecondRegistration() public {
        address t1 = erc721.addERC721TokenWrapped("AB", "C", "https://x/");
        assertTrue(t1 != address(0));
        vm.expectRevert("The current token already exists");
        erc721.addERC721TokenWrapped("A", "BC", "https://x/");
    }

    /// H-31: minting an NFT with an empty inscriptionId succeeds, but tokenURI
    /// then reverts ("tokenId is not exist") even though the token exists.
    function test_emptyInscriptionId_tokenURIReverts() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](1);
        insc[0] = "";
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
        assertEq(ERC721TokenWrapped(token).ownerOf(1), user);
        vm.expectRevert("tokenId is not exist");
        erc721.tokenURI(token, 1);
    }

    /// H-33: after burn, the same tokenId can be re-minted with a different
    /// inscriptionId (mappings are deleted on burn). Confirms re-mint is allowed.
    function test_burnThenRemintSameTokenId() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](1);
        insc[0] = "insc-1";
        uint256[] memory ids = new uint256[](1);
        ids[0] = 7;
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
        uint256[] memory burnIds = new uint256[](1);
        burnIds[0] = 7;
        erc721.batchBurnERC721Token(user, token, burnIds);
        string[] memory insc2 = new string[](1);
        insc2[0] = "insc-2";
        erc721.batchMintERC721Token(bytes32(uint256(2)), token, user, insc2, ids);
        assertEq(ERC721TokenWrapped(token).ownerOf(7), user);
        assertEq(erc721.tokenURI(token, 7), "https://x/insc-2");
    }

    /// H-34: duplicate tokenId inside one batch reverts the whole mint.
    function test_batchMintDuplicateTokenId_RevertsWholeBatch() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](2);
        insc[0] = "a";
        insc[1] = "b";
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 1;
        vm.expectRevert("tokenId is repeat");
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
        assertEq(ERC721TokenWrapped(token).balanceOf(user), 0);
    }

    /// H-35: duplicate inscriptionId inside one batch reverts the whole mint.
    function test_batchMintDuplicateInscriptionId_RevertsWholeBatch() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](2);
        insc[0] = "a";
        insc[1] = "a";
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        vm.expectRevert("inscriptionId is repeat");
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
    }

    /// H-36: minting past the cap reverts (ERC20Capped enforced).
    function test_mintPastCap_Reverts() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 100 ether);
        vm.expectRevert();
        erc20.mintERC20Token(bytes32(uint256(2)), token, user, 1);
    }

    /// H-37: replaying a txHash reverts.
    function test_mintTxHashReplay_Reverts() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 1 ether);
        vm.expectRevert("Transaction has been executed");
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 1 ether);
    }

    /// H-38: a txHash mints only once across ALL ERC20 tokens (global mapping).
    function test_mintTxHashSharedAcrossTokens() public {
        address t1 = erc20.addERC20TokenWrapped("T1", "T1", 18, 100 ether);
        address t2 = erc20.addERC20TokenWrapped("T2", "T2", 18, 100 ether);
        erc20.mintERC20Token(bytes32(uint256(1)), t1, user, 1 ether);
        vm.expectRevert("Transaction has been executed");
        erc20.mintERC20Token(bytes32(uint256(1)), t2, user, 1 ether);
    }

    /// H-39: blacklisted users cannot transfer OR burn (freeze is total for outflows).
    function test_blacklistBlocksTransferAndBurn() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 10 ether);
        erc20.setBlackListERC20Token(token, user, true);
        vm.prank(user);
        vm.expectRevert("from is in blackList");
        ERC20TokenWrapped(token).transfer(address(0xCAFE), 1 ether);
        vm.expectRevert("from is in blackList");
        erc20.burnERC20Token(user, token, 1 ether);
    }

    /// H-40: blacklisted users CAN still receive (mint + transfer-in work).
    function test_blacklistAllowsReceiving() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        erc20.setBlackListERC20Token(token, user, true);
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 10 ether);
        assertEq(ERC20TokenWrapped(token).balanceOf(user), 10 ether);
    }

    /// H-41: burning more than the balance reverts.
    function test_burnMoreThanBalance_Reverts() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        erc20.mintERC20Token(bytes32(uint256(1)), token, user, 1 ether);
        vm.expectRevert();
        erc20.burnERC20Token(user, token, 2 ether);
    }

    /// H-42: mint to the zero address reverts (OZ _mint guard).
    function test_mintToZeroAddress_Reverts() public {
        address token = erc20.addERC20TokenWrapped("T", "T", 18, 100 ether);
        vm.expectRevert();
        erc20.mintERC20Token(bytes32(uint256(1)), token, address(0), 1 ether);
    }

    /// H-43: burning an NFT the caller does not own reverts.
    function test_burnNftNotOwned_Reverts() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](1);
        insc[0] = "a";
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
        vm.expectRevert("Illegal permissions");
        erc721.batchBurnERC721Token(address(0xCAFE), token, ids);
    }

    /// H-44: burning the same NFT twice in one batch reverts the whole batch.
    function test_batchBurnDuplicateTokenId_RevertsWholeBatch() public {
        address token = erc721.addERC721TokenWrapped("N", "N", "https://x/");
        string[] memory insc = new string[](1);
        insc[0] = "a";
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        erc721.batchMintERC721Token(bytes32(uint256(1)), token, user, insc, ids);
        uint256[] memory burnIds = new uint256[](2);
        burnIds[0] = 1;
        burnIds[1] = 1;
        vm.expectRevert("Illegal permissions");
        erc721.batchBurnERC721Token(user, token, burnIds);
        assertEq(ERC721TokenWrapped(token).ownerOf(1), user);
    }

    /// H-45: setBaseURI through module A on a token deployed by module B reverts
    /// (the wrapped token only trusts its own deployer module as bridge).
    function test_setBaseURIOnForeignWrappedToken_Reverts() public {
        BTCLayer2BridgeERC721 erc721b = new BTCLayer2BridgeERC721();
        erc721b.initialize(address(this), bridge);
        address foreign = erc721b.addERC721TokenWrapped("F", "F", "https://f/");
        vm.expectRevert("TokenWrapped::onlyBridge: Not BTCLayer2Bridge");
        erc721.setBaseURI(foreign, "https://evil/");
    }

    /// H-46: setBaseURI on an address with no code reverts (solc 0.8.10+ inserts
    /// an extcodesize check on high-level calls). Admin-only path either way.
    function test_setBaseURIOnEOA_Reverts() public {
        vm.expectRevert();
        erc721.setBaseURI(address(0xCAFE), "https://evil/");
    }
}
