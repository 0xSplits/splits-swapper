// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {LibClone} from "src/utils/LibClone.sol";

contract LibCloneTest is Test {
    using LibClone for address;

    function setUp() public {}

    function testFuzz_clone(address impl) public {
        address clone = impl.clone();
        assertEq(
            clone.code,
            abi.encodePacked(
                hex"36602c57343d527f",
                // `keccak256("ReceiveETH(uint256)")`
                hex"9e4ac34f21c619cefc926c8bd93b54bf5a39c7ab2127a895af1cc0691d7e3dff",
                hex"593da1005b3d3d3d3d363d3d37363d73",
                impl,
                hex"5af43d3d93803e605757fd5bf3"
            )
        );
    }

    function testFuzz_cloneCanReceiveETH(address impl, uint96 ethValue) public {
        address clone = impl.clone();
        payable(clone).transfer(ethValue);
    }

    function testFuzz_cloneCanDelegateCall(address impl, bytes calldata data) public {
        vm.assume(data.length > 0);
        assumePayable(impl);

        address clone = impl.clone();

        vm.expectCall(impl, data);
        (bool success,) = clone.call(data);
        assertTrue(success);
    }
}
