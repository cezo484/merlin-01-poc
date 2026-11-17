// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

interface IBridge {
    function lockNativeToken(string memory destBtcAddr) external payable;
    function validBtcAddress(string memory _btcAddr) external view returns (bool);
    function bridgeFee() external view returns (uint256);
}

/// @notice Fork tests against the live MerlinChain BTCLayer2Bridge proxy.
/// @dev Run with: forge test --fork-url https://rpc.merlinchain.io -vvv
///      All calls run on a LOCAL fork. No mainnet transaction is sent.
contract TrackA01ForkTest is Test {
    address constant BRIDGE = 0x28AD6b7dfD79153659cb44C2155cf7C0e1CeEccC;
    address user;

    // Addresses that Bitcoin Core rejects but the on-chain checker accepts.
    // Each one has a VALID checksum; the defect is a missing length rule.
    string constant B58_1BYTE = "112edB6q"; // base58check, version 0x00, 1-byte payload
    string constant B58_19BYTE = "111111111111111111117K4nzc"; // P2PKH, 19-byte hash
    string constant B58_21BYTE = "11111111111111111111116iowaD"; // P2PKH, 21-byte hash
    string constant V0_31BYTE = "bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpqy20t"; // v0, 31-byte program
    string constant V0_2BYTE = "bc1qqqqq399cqn"; // v0, 2-byte program
    string constant V1_20BYTE = "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kj9wkru"; // v1, 20-byte program
    string constant V0_40BYTE = "bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsw47qg"; // v0, 40-byte program

    // Controls
    string constant VALID_P2PKH = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa";
    string constant VALID_BECH32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq";
    string constant BAD_CHECKSUM = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb";

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 10 ether);
    }

    function test_checkerAcceptsInvalidBase58() public view {
        assertTrue(IBridge(BRIDGE).validBtcAddress(B58_1BYTE), "1-byte payload accepted");
        assertTrue(IBridge(BRIDGE).validBtcAddress(B58_19BYTE), "19-byte hash accepted");
        assertTrue(IBridge(BRIDGE).validBtcAddress(B58_21BYTE), "21-byte hash accepted");
    }

    function test_checkerAcceptsInvalidSegwitPrograms() public view {
        assertTrue(IBridge(BRIDGE).validBtcAddress(V0_31BYTE), "v0 31-byte program accepted");
        assertTrue(IBridge(BRIDGE).validBtcAddress(V0_2BYTE), "v0 2-byte program accepted");
        assertTrue(IBridge(BRIDGE).validBtcAddress(V1_20BYTE), "v1 20-byte program accepted");
        assertTrue(IBridge(BRIDGE).validBtcAddress(V0_40BYTE), "v0 40-byte program accepted");
    }

    function test_lockSucceedsWithInvalidBase58() public {
        uint256 fee = IBridge(BRIDGE).bridgeFee();
        uint256 balBefore = address(BRIDGE).balance;
        vm.prank(user);
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(B58_1BYTE);
        assertEq(address(BRIDGE).balance, balBefore + 0.01 ether - fee, "bridge kept the locked BTC");
    }

    function test_lockSucceedsWithInvalidSegwit() public {
        uint256 fee = IBridge(BRIDGE).bridgeFee();
        uint256 balBefore = address(BRIDGE).balance;
        vm.prank(user);
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(V0_31BYTE);
        assertEq(address(BRIDGE).balance, balBefore + 0.01 ether - fee, "bridge kept the locked BTC");
    }

    function test_lockSucceedsWithAnyoneCanSpendTaproot() public {
        uint256 fee = IBridge(BRIDGE).bridgeFee();
        uint256 balBefore = address(BRIDGE).balance;
        vm.prank(user);
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(V1_20BYTE);
        assertEq(address(BRIDGE).balance, balBefore + 0.01 ether - fee, "bridge kept the locked BTC");
    }

    function test_controlValidAddressLocks() public {
        uint256 fee = IBridge(BRIDGE).bridgeFee();
        uint256 balBefore = address(BRIDGE).balance;
        vm.prank(user);
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(VALID_P2PKH);
        assertEq(address(BRIDGE).balance, balBefore + 0.01 ether - fee, "valid lock works");
        vm.prank(user);
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(VALID_BECH32);
        assertEq(address(BRIDGE).balance, balBefore + 0.02 ether - 2 * fee, "valid bech32 lock works");
    }

    function test_controlBadChecksumReverts() public {
        assertFalse(IBridge(BRIDGE).validBtcAddress(BAD_CHECKSUM), "bad checksum rejected");
        vm.prank(user);
        vm.expectRevert("Invalid destBtcAddr");
        IBridge(BRIDGE).lockNativeToken{value: 0.01 ether}(BAD_CHECKSUM);
    }
}
