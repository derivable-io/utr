// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./interfaces/IUniversalTokenRouter.sol";

contract UniversalTokenRouter is IUniversalTokenRouter {
    uint constant INPUT_PARAMS_PLACEHOLDER = uint(keccak256('UniversalTokenRouter.INPUT_PARAMS_PLACEHOLDER'));

    function exec(
        Action[] calldata actions
    ) override external payable returns (
        uint[][] memory results,
        uint gasLeft
    ) { unchecked {
        results = new uint[][](actions.length);
        uint value; // track the ETH value to pass to next output action transaction value
        bytes memory inputParams;
        for (uint i = 0; i < actions.length; ++i) {
            Action memory action = actions[i];
            results[i] = new uint[](action.tokens.length);
            if (action.inputOffset < 32) {
                // output action
                for (uint j = 0; j < action.tokens.length; ++j) {
                    Token memory token = action.tokens[j];
                    if (token.amount > 0) {
                        // track the recipient balance before the action is executed
                        results[i][j] = _balanceOf(token);
                    }
                }
                if (action.data.length > 0) {
                    uint length = action.data.length;
                    if (length >= 4+32*3 &&
                        _sliceUint(action.data, length) == INPUT_PARAMS_PLACEHOLDER &&
                        _sliceUint(action.data, length-32) == 32)
                    {
                        action.data = _concat(action.data, length-32, inputParams);
                    }
                    (bool success, bytes memory result) = action.code.call{value: value}(action.data);
                    // ignore output action error if the first bit of inputOffset is not set
                    if (!success && (action.inputOffset & 0x1) == 0) {
                        assembly {
                            revert(add(result,32),mload(result))
                        }
                    }
                    delete value; // clear the ETH value after transfer
                }
                continue;
            }
            // input action
            if (action.data.length > 0) {
                bool success;
                (success, inputParams) = action.code.call(action.data);
                if (!success) {
                    assembly {
                        revert(add(inputParams,32),mload(inputParams))
                    }
                }
            }
            for (uint j = 0; j < action.tokens.length; ++j) {
                Token memory token = action.tokens[j];
                // input action
                if (action.data.length > 0) {
                    uint amount = _sliceUint(inputParams, action.inputOffset + j*32);
                    require(amount <= token.amount, "UniversalTokenRouter: EXCESSIVE_INPUT_AMOUNT");
                    token.amount = amount;
                }
                results[i][j] = token.amount;
                if (token.eip == 0 && token.recipient == address(0x0)) {
                    value = token.amount;
                    continue; // ETH not transfered here will be passed to the next output call value
                }
                if (token.amount > 0) {
                    _transfer(token);
                }
            }
        }
        // refund any left-over ETH
        uint leftOver = address(this).balance;
        if (leftOver > 0) {
            TransferHelper.safeTransferETH(msg.sender, leftOver);
        }
        // verify the balance change
        for (uint i = 0; i < actions.length; ++i) {
            if (actions[i].inputOffset >= 32) {
                continue;
            }
            for (uint j = 0; j < actions[i].tokens.length; ++j) {
                Token memory token = actions[i].tokens[j];
                if (token.amount == 0) {
                    continue;
                }
                uint balance = _balanceOf(token);
                uint change = balance - results[i][j]; // overflow checked with `change <= balance` bellow
                require(change >= token.amount && change <= balance, 'UniversalTokenRouter: INSUFFICIENT_OUTPUT_AMOUNT');
                results[i][j] = change;
            }
        }
        gasLeft = gasleft();
    } }

    // https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
    function _concat(
        bytes memory preBytes,
        uint length,
        bytes memory postBytes
    )
        internal
        pure
        returns (bytes memory bothBytes)
    {
        assembly {
            // Get a location of some free memory and store it in bothBytes as
            // Solidity does for memory variables.
            bothBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for bothBytes.
            mstore(bothBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(bothBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the preBytes data,
                // 32 bytes into its memory.
                let cc := add(preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the preBytes data into the bothBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of postBytes to the current length of bothBytes
            // and store it as the new length in the first 32 bytes of the
            // bothBytes memory.
            length := mload(postBytes)
            mstore(bothBytes, add(length, mload(bothBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the preBytes data.
            mc := sub(end, 0x20)
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(end, length)

            for {
                let cc := postBytes
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of bothBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(0x40, and(
              add(add(end, iszero(add(length, mload(preBytes)))), 31),
              not(31) // Round down to the nearest 32 bytes.
            ))
        }
    }

    // https://ethereum.stackexchange.com/a/54405
    function _sliceUint(bytes memory bs, uint start) internal pure returns (uint x) {
    unchecked {
        // require(bs.length >= start + 32, "slicing out of range");
        assembly {
            x := mload(add(bs, start))
        }
    } }

    function _transfer(Token memory token) internal {
    unchecked {
        if (token.eip == 20) {
            TransferHelper.safeTransferFrom(token.adr, msg.sender, token.recipient, token.amount);
        } else if (token.eip == 1155) {
            IERC1155(token.adr).safeTransferFrom(msg.sender, token.recipient, token.id, token.amount, "");
        } else if (token.eip == 721) {
            IERC721(token.adr).safeTransferFrom(msg.sender, token.recipient, token.id);
        } else if (token.eip == 0) {
            TransferHelper.safeTransferETH(token.recipient, token.amount);
        } else {
            revert("UniversalTokenRouter: INVALID_EIP");
        }
    } }

    function _balanceOf(Token memory token) internal view returns (uint balance) {
    unchecked {
        if (token.eip == 20) {
            return IERC20(token.adr).balanceOf(token.recipient);
        }
        if (token.eip == 1155) {
            return IERC1155(token.adr).balanceOf(token.recipient, token.id);
        }
        if (token.eip == 721) {
            return IERC721(token.adr).ownerOf(token.id) == token.recipient ? 1 : 0;
        }
        if (token.eip == 0) {
            return token.recipient.balance;
        }
        revert("UniversalTokenRouter: INVALID_EIP");
    } }
}
