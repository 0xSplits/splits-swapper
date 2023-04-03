// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {LibClone} from "src/utils/LibClone.sol";
import {PausableImpl} from "src/utils/PausableImpl.sol";

contract PausableImplTest is Test {
    using LibClone for address;

    PausableImplHarness public pausableImpl;
    PausableImplHarness public pausable;

    error Unauthorized();
    error Paused();

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event SetPaused(bool paused);

    function setUp() public virtual {
        pausableImpl = new PausableImplHarness();
        pausable = PausableImplHarness(address(pausableImpl).clone());
    }

    /// -----------------------------------------------------------------------
    /// modifiers
    /// -----------------------------------------------------------------------

    modifier callerOwner() {
        _;
    }

    /// -----------------------------------------------------------------------
    /// tests - basic
    /// -----------------------------------------------------------------------

    function test_init_setsOwner() public {
        pausable.exposed_initPausable(address(this), true);
        assertEq(pausable.$owner(), address(this));
    }

    function test_init_emitsOwnershipTransferred() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(0), address(this));
        pausable.exposed_initPausable(address(this), true);
    }

    function test_init_setsPaused() public {
        pausable.exposed_initPausable(address(this), true);
        assertEq(pausable.$paused(), true);
    }

    function test_RevertWhen_CallerNotOwner_setPaused() public {
        vm.expectRevert(Unauthorized.selector);
        pausable.setPaused(true);
    }

    function test_setPaused_setsPaused() public callerOwner {
        pausable.exposed_initPausable(address(this), true);

        pausable.setPaused(false);
        assertEq(pausable.$paused(), false);
    }

    function test_setPaused_emitsSetPaused() public callerOwner {
        pausable.exposed_initPausable(address(this), false);

        vm.expectEmit(true, true, true, true);
        emit SetPaused(true);
        pausable.setPaused(true);
    }

    /// -----------------------------------------------------------------------
    /// tests - fuzz
    /// -----------------------------------------------------------------------

    function testFuzz_init_setsOwner(address owner_, bool paused_) public {
        pausable.exposed_initPausable(owner_, paused_);
        assertEq(pausable.$owner(), owner_);
    }

    function testFuzz_init_emitsOwnershipTransferred(address owner_, bool paused_) public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(0), owner_);
        pausable.exposed_initPausable(owner_, paused_);
    }

    function testFuzz_init_setsPaused(address owner_, bool paused_) public {
        pausable.exposed_initPausable(owner_, paused_);
        assertEq(pausable.$paused(), paused_);
    }

    function testFuzz_RevertWhen_CallerNotOwner_setPaused(address owner_, address prankOwner_, bool paused_) public {
        vm.assume(owner_ != prankOwner_);

        pausable.exposed_initPausable(owner_, paused_);

        vm.prank(prankOwner_);
        vm.expectRevert(Unauthorized.selector);
        pausable.setPaused(paused_);
    }

    function testFuzz_setPaused_setsPaused(address owner_, bool paused_) public callerOwner {
        pausable.exposed_initPausable(owner_, false);

        vm.prank(owner_);
        pausable.setPaused(paused_);
        assertEq(pausable.$paused(), paused_);
    }

    function testFuzz_setPaused_emitsSetPaused(address owner_, bool paused_) public callerOwner {
        pausable.exposed_initPausable(owner_, paused_);

        vm.expectEmit(true, true, true, true);
        vm.prank(owner_);
        emit SetPaused(paused_);
        pausable.setPaused(paused_);
    }
}

contract PausableImplHarness is PausableImpl {
    function exposed_initPausable(address owner_, bool paused_) external {
        __initPausable(owner_, paused_);
    }
}
