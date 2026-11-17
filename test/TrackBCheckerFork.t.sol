// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

interface IBridge {
    function burnERC20Token(address token, uint256 amount, string memory destBtcAddr) external payable;
    function getBridgeFee(address msgSender, address token) external view returns (uint256);
    function validBtcAddress(string memory btcAddr) external view returns (bool);
}

interface IERC20Mini {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Fork tests against Merlin Chain mainnet state.
/// @dev The bridge accepts bridge-out to Bitcoin addresses that are invalid
///      under Bitcoin consensus rules (wrong witness-program length, wrong
///      base58 payload length) as long as the checksum is valid. The wrapped
///      tokens are burned on L2 while the L1 release can never be spent.
///      Run with: forge test --match-contract TrackBCheckerFork -vvv
///      (needs MERLIN_RPC_URL; fork block pinned in the test)
contract TrackBCheckerForkTest is Test {
    IBridge constant BRIDGE = IBridge(0x28AD6b7dfD79153659cb44C2155cf7C0e1CeEccC);
    address constant MBTC = 0xB880fd278198bd590252621d4CD071b1842E9Bcd;

    // v0 segwit, 19-byte program, VALID bech32 checksum. BIP141 requires
    // v0 programs to be exactly 20 or 32 bytes, so this output is unspendable.
    string constant BAD_BECH32_V0_19 = "bc1qw508d6qejxtdg4y5r3zarvary0c5xwck8mzle";
    // v1 segwit, EMPTY program, VALID bech32m checksum. Programs must be 2-40 bytes.
    string constant BAD_BECH32M_V1_EMPTY = "bc1pdg93mv";
    // base58check, valid checksum, but 24 bytes total instead of 25.
    string constant BAD_B58_24B = "11GsChQR2U32pvwJcDNPoYHhGcnz5Rv";
    // v0 segwit, 20-byte program, valid bech32 checksum (control: valid address).
    string constant GOOD_BECH32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq";
    // P2PKH with a broken checksum (control: invalid address, must revert).
    string constant BAD_CHECKSUM = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb";

    address user = address(0xBEEF);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MERLIN_RPC_URL"), 33092000);
        vm.selectFork(forkId);
        deal(MBTC, user, 10 ether);
        deal(user, 1 ether);
    }

    function _burn(string memory dest) internal {
        uint256 fee = BRIDGE.getBridgeFee(user, MBTC);
        vm.prank(user);
        BRIDGE.burnERC20Token{value: fee}(MBTC, 1 ether, dest);
    }

    function test_burnToInvalidBech32V0_19_Succeeds() public {
        assertTrue(BRIDGE.validBtcAddress(BAD_BECH32_V0_19), "checker should (wrongly) accept v0 19-byte");
        uint256 beforeBal = IERC20Mini(MBTC).balanceOf(user);
        _burn(BAD_BECH32_V0_19);
        assertEq(IERC20Mini(MBTC).balanceOf(user), beforeBal - 1 ether, "M-BTC must be burned");
    }

    function test_burnToInvalidBech32mV1Empty_Succeeds() public {
        assertTrue(BRIDGE.validBtcAddress(BAD_BECH32M_V1_EMPTY), "checker should (wrongly) accept v1 empty");
        uint256 beforeBal = IERC20Mini(MBTC).balanceOf(user);
        _burn(BAD_BECH32M_V1_EMPTY);
        assertEq(IERC20Mini(MBTC).balanceOf(user), beforeBal - 1 ether, "M-BTC must be burned");
    }

    function test_burnToInvalidBase58_24B_Succeeds() public {
        assertTrue(BRIDGE.validBtcAddress(BAD_B58_24B), "checker should (wrongly) accept 24-byte base58");
        uint256 beforeBal = IERC20Mini(MBTC).balanceOf(user);
        _burn(BAD_B58_24B);
        assertEq(IERC20Mini(MBTC).balanceOf(user), beforeBal - 1 ether, "M-BTC must be burned");
    }

    function test_burnToValidAddress_Succeeds() public {
        assertTrue(BRIDGE.validBtcAddress(GOOD_BECH32), "checker must accept a valid address");
        uint256 beforeBal = IERC20Mini(MBTC).balanceOf(user);
        _burn(GOOD_BECH32);
        assertEq(IERC20Mini(MBTC).balanceOf(user), beforeBal - 1 ether, "M-BTC must be burned");
    }

    function test_burnToBadChecksum_Reverts() public {
        assertFalse(BRIDGE.validBtcAddress(BAD_CHECKSUM), "checker must reject a bad checksum");
        uint256 fee = BRIDGE.getBridgeFee(user, MBTC);
        vm.prank(user);
        vm.expectRevert("Invalid destBtcAddr");
        BRIDGE.burnERC20Token{value: fee}(MBTC, 1 ether, BAD_CHECKSUM);
    }
}
