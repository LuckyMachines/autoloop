// Sources flattened with hardhat v2.12.5 https://hardhat.org

// File @openzeppelin/contracts/access/IAccessControl.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/IAccessControl.sol)

pragma solidity ^0.8.0;

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}

// File @openzeppelin/contracts/utils/Context.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// File @openzeppelin/contracts/utils/introspection/ERC165.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// File @openzeppelin/contracts/utils/math/Math.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1);

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator,
        Rounding rounding
    ) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(
        uint256 a,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return
                result +
                (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return
                result +
                (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return
                result +
                (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return
                result +
                (rounding == Rounding.Up && 1 << (result * 8) < value ? 1 : 0);
        }
    }
}

// File @openzeppelin/contracts/utils/Strings.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(
        uint256 value,
        uint256 length
    ) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

// File @openzeppelin/contracts/access/AccessControl.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (access/AccessControl.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IAccessControl).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(
        bytes32 role,
        address account
    ) public view virtual override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `_msgSender()` is missing `role`.
     * Overriding this function changes the behavior of the {onlyRole} modifier.
     *
     * Format of the revert message is described in {_checkRole}.
     *
     * _Available since v4.6._
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(
        bytes32 role
    ) public view virtual override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(
        bytes32 role,
        address account
    ) public virtual override {
        require(
            account == _msgSender(),
            "AccessControl: can only renounce roles for self"
        );

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * May emit a {RoleGranted} event.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     *
     * NOTE: This function is deprecated in favor of {_grantRole}.
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

// File @openzeppelin/contracts/access/IAccessControlEnumerable.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/IAccessControlEnumerable.sol)

pragma solidity ^0.8.0;

/**
 * @dev External interface of AccessControlEnumerable declared to support ERC165 detection.
 */
interface IAccessControlEnumerable is IAccessControl {
    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(
        bytes32 role,
        uint256 index
    ) external view returns (address);

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

// File @openzeppelin/contracts/utils/structs/EnumerableSet.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/structs/EnumerableSet.sol)
// This file was procedurally generated from scripts/generate/templates/EnumerableSet.js.

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an
 * array of EnumerableSet.
 * ====
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastValue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastValue;
                // Update the index for the moved value
                set._indexes[lastValue] = valueIndex; // Replace lastValue's index to valueIndex
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(
        Set storage set,
        bytes32 value
    ) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(
        Set storage set,
        uint256 index
    ) private view returns (bytes32) {
        return set._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(
        Bytes32Set storage set,
        bytes32 value
    ) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(
        Bytes32Set storage set,
        bytes32 value
    ) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(
        Bytes32Set storage set,
        bytes32 value
    ) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(
        Bytes32Set storage set,
        uint256 index
    ) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(
        Bytes32Set storage set
    ) internal view returns (bytes32[] memory) {
        bytes32[] memory store = _values(set._inner);
        bytes32[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(
        AddressSet storage set,
        address value
    ) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(
        AddressSet storage set,
        address value
    ) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(
        AddressSet storage set,
        address value
    ) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(
        AddressSet storage set,
        uint256 index
    ) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(
        AddressSet storage set
    ) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(
        UintSet storage set,
        uint256 value
    ) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(
        UintSet storage set,
        uint256 value
    ) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(
        UintSet storage set,
        uint256 index
    ) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(
        UintSet storage set
    ) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }
}

// File @openzeppelin/contracts/access/AccessControlEnumerable.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (access/AccessControlEnumerable.sol)

pragma solidity ^0.8.0;

/**
 * @dev Extension of {AccessControl} that allows enumerating the members of each role.
 */
abstract contract AccessControlEnumerable is
    IAccessControlEnumerable,
    AccessControl
{
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => EnumerableSet.AddressSet) private _roleMembers;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IAccessControlEnumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(
        bytes32 role,
        uint256 index
    ) public view virtual override returns (address) {
        return _roleMembers[role].at(index);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(
        bytes32 role
    ) public view virtual override returns (uint256) {
        return _roleMembers[role].length();
    }

    /**
     * @dev Overload {_grantRole} to track enumerable memberships
     */
    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override {
        super._grantRole(role, account);
        _roleMembers[role].add(account);
    }

    /**
     * @dev Overload {_revokeRole} to track enumerable memberships
     */
    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override {
        super._revokeRole(role, account);
        _roleMembers[role].remove(account);
    }
}

// File @openzeppelin/contracts/security/ReentrancyGuard.sol@v4.8.1

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File contracts/AutoLoopRoles.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract AutoLoopRoles is AccessControlEnumerable {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRY_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    // Admin
    function setRegistrar(
        address registrarAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REGISTRAR_ROLE, registrarAddress);
    }

    function removeRegistrar(
        address registrarAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REGISTRAR_ROLE, registrarAddress);
    }
}

// File contracts/AutoLoop.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract AutoLoop is AutoLoopRoles, ReentrancyGuard {
    event AutoLoopProgressed(
        address indexed autoLoopCompatibleContract,
        uint256 indexed timeStamp,
        address controller,
        uint256 gasUsed,
        uint256 gasPrice,
        uint256 gasCost,
        uint256 fee
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    uint256 BASE_FEE = 70; // percentage of gas cost used
    uint256 PROTOCOL_FEE_PORTION = 60; // percentage of base fee to go to protocol
    uint256 CONTROLLER_FEE_PORTION = 40; // percentage of base fee to go to controller
    uint256 MAX_GAS = 1_000_000; // default if no personal max set
    uint256 GAS_BUFFER = 122_100; // gas required to run transaction outside of contract update
    uint256 GAS_THRESHOLD = 15_000_000 - GAS_BUFFER; // highest a user could potentially set gas

    mapping(address => uint256) public balance; // balance held at this address
    mapping(address => uint256) public maxGas; // max gas a user is willing to spend on tx

    uint256 _protocolBalance;

    // PUBLIC //
    function baseFee() public view returns (uint256) {
        return BASE_FEE;
    }

    function gasBuffer() public view returns (uint256) {
        return GAS_BUFFER;
    }

    function gasThreshold() public view returns (uint256) {
        return GAS_THRESHOLD;
    }

    function maxGasDefault() public view returns (uint256) {
        return MAX_GAS;
    }

    function maxGasFor(address userAddress) public view returns (uint256) {
        if (maxGas[userAddress] == 0) {
            return MAX_GAS;
        } else {
            return maxGas[userAddress];
        }
    }

    /**
     * @notice progresses loop on AutoLoop compatible contract
     * @param contractAddress the address of the contract receiving update
     * @param progressWithData some data to pass along with update
     */
    function progressLoop(
        address contractAddress,
        bytes calldata progressWithData
    ) external onlyRole(CONTROLLER_ROLE) nonReentrant {
        // console.log("Progressing Loop %s", contractAddress);

        uint256 gasUsed = GAS_BUFFER;
        uint256 startGas = gasleft();
        // progress loop on contract
        (bool success, ) = contractAddress.call(
            abi.encodeWithSignature("progressLoop(bytes)", progressWithData)
        );
        // Calculate this first to get cost of update + this function
        gasUsed += (startGas - gasleft());

        require(success, "Unable to progress loop. Call not a success");

        uint256 gasCost = gasUsed * tx.gasprice;
        uint256 fee = (gasCost * BASE_FEE) / 100; //total fee for controller + protocol
        uint256 controllerFee = (fee * CONTROLLER_FEE_PORTION) / 100; // controller's portion of fee
        uint256 totalCost = gasCost + fee; // total cost including fee

        require(
            balance[contractAddress] >= totalCost,
            "AutoLoop compatible contract balance too low to run update + fee."
        );
        balance[contractAddress] -= totalCost;
        (bool sent, ) = _msgSender().call{value: gasCost + controllerFee}("");
        require(sent, "Failed to repay controller");

        _protocolBalance += (fee - controllerFee);

        emit AutoLoopProgressed(
            contractAddress,
            block.timestamp,
            _msgSender(),
            gasUsed,
            tx.gasprice,
            gasCost,
            fee
        );
    }

    // REGISTRAR //
    function addController(
        address controllerAddress
    ) public onlyRole(REGISTRAR_ROLE) {
        _grantRole(CONTROLLER_ROLE, controllerAddress);
    }

    function removeController(
        address controllerAddress
    ) public onlyRole(REGISTRAR_ROLE) {
        _revokeRole(CONTROLLER_ROLE, controllerAddress);
    }

    function deposit(
        address registeredUser
    ) external payable onlyRole(REGISTRAR_ROLE) {
        balance[registeredUser] += msg.value;
    }

    function requestRefund(
        address registeredUser,
        address toAddress
    ) external onlyRole(REGISTRAR_ROLE) nonReentrant {
        require(balance[registeredUser] > 0, "User balance is zero.");
        (bool sent, ) = toAddress.call{value: balance[registeredUser]}("");
        require(sent, "Failed to send refund");
        balance[registeredUser] = 0;
    }

    function setMaxGas(
        address registerdUser,
        uint256 maxGasAmount
    ) external onlyRole(REGISTRAR_ROLE) {
        maxGas[registerdUser] = maxGasAmount > GAS_THRESHOLD
            ? GAS_THRESHOLD
            : maxGasAmount;
    }

    // ADMIN //
    function setControllerFeePortion(
        uint256 controllerFeePercentage
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            controllerFeePercentage <= 100,
            "Percentage should be less than or equal to 100"
        );
        CONTROLLER_FEE_PORTION = controllerFeePercentage;
        PROTOCOL_FEE_PORTION = 100 - CONTROLLER_FEE_PORTION;
    }

    function setProtocolFeePortion(
        uint256 protocolFeePortion
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            protocolFeePortion <= 100,
            "Percentage should be less than or equal to 100"
        );
        PROTOCOL_FEE_PORTION = protocolFeePortion;
        CONTROLLER_FEE_PORTION = 100 - PROTOCOL_FEE_PORTION;
    }

    function setMaxGasDefault(
        uint256 maxGasDefaultValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        MAX_GAS = maxGasDefaultValue;
    }

    function setGasBuffer(
        uint256 gasBufferValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        GAS_BUFFER = gasBufferValue;
    }

    function setGasThreshold(
        uint256 gasThresholdValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        GAS_THRESHOLD = gasThresholdValue;
    }

    function withdrawProtocolFees(
        uint256 amount,
        address toAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(
            _protocolBalance >= amount,
            "withdraw amount greater than protocol balance"
        );
        (bool sent, ) = toAddress.call{value: _protocolBalance}("");
        require(sent, "Error withdrawing protocol fees");
        _protocolBalance -= amount;
    }

    // Internal //

    // returns usable amount of gas given a total gas amount (removes the fee)
    function _usableGas(
        uint256 totalGas
    ) internal view returns (uint256 gasAmount) {
        gasAmount = (totalGas * 100) / (100 + BASE_FEE);
    }

    function _maxGas(address user) internal view returns (uint256 gasAmount) {
        gasAmount = maxGas[user] > 0 ? maxGas[user] : MAX_GAS;

        if (gasAmount * tx.gasprice > balance[user]) {
            gasAmount = balance[user] / tx.gasprice;
        }
    }
}

// File contracts/AutoLoopCompatibleInterface.sol

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface AutoLoopCompatibleInterface {
    function shouldProgressLoop()
        external
        view
        returns (bool loopIsReady, bytes memory progressWithData);

    // No guarantees on the data passed in. Should not be solely relied on.
    // Re-verify any data passed through progressWithData.
    function progressLoop(bytes calldata progressWithData) external;
}

// File contracts/AutoLoopCompatible.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract AutoLoopCompatible is
    AutoLoopCompatibleInterface,
    AccessControlEnumerable
{
    address public adminTransferRequestOrigin;
    address public adminTransferRequest;

    uint256 _loopID;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _loopID = 1;
    }

    function safeTransferAdmin(address newAdminAddress) public {
        require(
            adminTransferRequest == address(0),
            "current request in progress. can't transfer until complete or cancelled."
        );
        require(
            newAdminAddress != address(0),
            "cannot transfer admin to zero address"
        );
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only current admin can transfer their role"
        );
        adminTransferRequestOrigin = _msgSender();
        adminTransferRequest = newAdminAddress;
    }

    function acceptTransferAdminRequest() public {
        require(
            _msgSender() == adminTransferRequest,
            "Only new admin can accept transfer request"
        );
        require(
            adminTransferRequestOrigin != address(0),
            "No pending transfer request to accept."
        );
        _revokeRole(DEFAULT_ADMIN_ROLE, adminTransferRequestOrigin);
        _setupRole(DEFAULT_ADMIN_ROLE, adminTransferRequest);
        adminTransferRequestOrigin = address(0);
        adminTransferRequest = address(0);
    }

    function cancelTransferAdminRequest() public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only current admin can cancel transfer request"
        );
        adminTransferRequest = address(0);
        adminTransferRequestOrigin = address(0);
    }
}

// File contracts/AutoLoopRegistry.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract AutoLoopRegistry is AutoLoopRoles {
    // Mappings from registered AutoLoop or Controller Addresses
    mapping(address => bool) public isRegisteredAutoLoop;
    mapping(address => bool) public isRegisteredController;
    mapping(address => bool) public wasRegisteredAutoLoop;
    mapping(address => bool) public wasRegisteredController;

    mapping(address => uint256) _registeredAutoLoopIndex;
    mapping(address => uint256) _registeredControllerIndex;

    // All registered AutoLoops
    address[] _registeredAutoLoops;
    address[] _registeredControllers;

    // mapping from admin to _registeredAutoLoops indices
    // this is a historical record, doesn't indicate current admin status
    mapping(address => uint256[]) _registeredAutoLoopsForAddress;

    event AutoLoopRegistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event AutoLoopDeregistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerRegistered(
        address controllerAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerDeregistered(
        address controllerAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    constructor(address adminAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    // Public
    function getRegisteredAutoLoops()
        public
        view
        returns (address[] memory autoLoops)
    {
        uint256 availableLoops = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            if (
                _registeredAutoLoops[i] != address(0) &&
                isRegisteredAutoLoop[_registeredAutoLoops[i]]
            ) {
                ++availableLoops;
            }
        }
        autoLoops = new address[](availableLoops);
        uint256 index = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            if (
                _registeredAutoLoops[i] != address(0) &&
                isRegisteredAutoLoop[_registeredAutoLoops[i]]
            ) {
                autoLoops[index] = _registeredAutoLoops[i];
                ++index;
            }
        }
    }

    function getRegisteredAutoLoopsExcludingList(
        address[] memory blockList
    ) public view returns (address[] memory autoLoops) {
        uint256 availableLoops = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            bool notBlocked = true;
            for (uint256 j = 0; j < blockList.length; j++) {
                if (blockList[j] == _registeredAutoLoops[i]) {
                    notBlocked = false;
                    break;
                }
            }
            if (
                notBlocked &&
                _registeredAutoLoops[i] != address(0) &&
                isRegisteredAutoLoop[_registeredAutoLoops[i]]
            ) {
                ++availableLoops;
            }
        }
        autoLoops = new address[](availableLoops);
        uint256 index = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            bool notBlocked = true;
            for (uint256 j = 0; j < blockList.length; j++) {
                if (blockList[j] == _registeredAutoLoops[i]) {
                    notBlocked = false;
                    break;
                }
            }
            if (
                notBlocked &&
                _registeredAutoLoops[i] != address(0) &&
                isRegisteredAutoLoop[_registeredAutoLoops[i]]
            ) {
                autoLoops[index] = _registeredAutoLoops[i];
                ++index;
            }
        }
    }

    function getRegisteredAutoLoopsFromList(
        address[] memory allowList
    ) public view returns (address[] memory autoLoops) {
        uint256 availableLoops = 0;
        for (uint256 i = 0; i < allowList.length; i++) {
            if (
                allowList[i] != address(0) && isRegisteredAutoLoop[allowList[i]]
            ) {
                ++availableLoops;
            }
        }
        autoLoops = new address[](availableLoops);
        uint256 index = 0;
        for (uint256 i = 0; i < allowList.length; i++) {
            if (
                allowList[i] != address(0) && isRegisteredAutoLoop[allowList[i]]
            ) {
                autoLoops[index] = allowList[i];
                ++index;
            }
        }
    }

    function getRegisteredAutoLoopIndicesFor(
        address adminAddress
    ) public view returns (uint256[] memory) {
        return _registeredAutoLoopsForAddress[adminAddress];
    }

    function getRegisteredAutoLoopsFor(
        address adminAddress
    ) public view returns (address[] memory autoLoops) {
        uint256 totalRegistrations = 0;
        uint256[] memory registeredLoops = _registeredAutoLoopsForAddress[
            adminAddress
        ];
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (
                compatibleContract.hasRole(DEFAULT_ADMIN_ROLE, adminAddress) &&
                isRegisteredAutoLoop[_registeredAutoLoops[registeredLoops[i]]]
            ) {
                ++totalRegistrations;
            }
        }
        autoLoops = new address[](totalRegistrations);
        uint256 outputIndex = 0;
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (
                compatibleContract.hasRole(DEFAULT_ADMIN_ROLE, adminAddress) &&
                isRegisteredAutoLoop[_registeredAutoLoops[registeredLoops[i]]]
            ) {
                autoLoops[outputIndex] = _registeredAutoLoops[
                    registeredLoops[i]
                ];
                ++outputIndex;
            }
        }
    }

    function getAdminTransferPendingAutoLoopsFor(
        address pendingAdminAddress
    ) public view returns (address[] memory autoLoops) {
        uint256 totalContracts = 0;
        uint256[] memory registeredLoops = _registeredAutoLoopsForAddress[
            pendingAdminAddress
        ];
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (
                compatibleContract.adminTransferRequest() == pendingAdminAddress
            ) {
                ++totalContracts;
            }
        }
        autoLoops = new address[](totalContracts);
        uint256 outputIndex = 0;
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (
                compatibleContract.adminTransferRequest() == pendingAdminAddress
            ) {
                autoLoops[outputIndex] = _registeredAutoLoops[
                    registeredLoops[i]
                ];
                ++outputIndex;
            }
        }
    }

    function getRegisteredControllers()
        public
        view
        returns (address[] memory controllers)
    {
        uint256 availableAddresses = 0;
        for (uint256 i = 0; i < _registeredControllers.length; i++) {
            if (
                _registeredControllers[i] != address(0) &&
                isRegisteredController[_registeredControllers[i]]
            ) {
                ++availableAddresses;
            }
        }
        controllers = new address[](availableAddresses);
        uint256 index = 0;
        for (uint256 i = 0; i < _registeredControllers.length; i++) {
            if (
                _registeredControllers[i] != address(0) &&
                isRegisteredController[_registeredControllers[i]]
            ) {
                controllers[index] = _registeredControllers[i];
                ++index;
            }
        }
    }

    function primaryAdmin(
        address autoLoopCompatibleAddress
    ) public view returns (address) {
        return
            AutoLoopCompatible(autoLoopCompatibleAddress).getRoleMember(
                DEFAULT_ADMIN_ROLE,
                0
            );
    }

    function allAdmins(
        address autoLoopCompatibleAddress
    ) public view returns (address[] memory) {
        AutoLoopCompatible alcc = AutoLoopCompatible(autoLoopCompatibleAddress);
        uint256 totalAdmins = alcc.getRoleMemberCount(DEFAULT_ADMIN_ROLE);
        address[] memory admins = new address[](totalAdmins);
        for (uint256 i = 0; i < totalAdmins; i++) {
            admins[i] = alcc.getRoleMember(DEFAULT_ADMIN_ROLE, i);
        }
        return admins;
    }

    // Cleanup
    // TODO: remove zero addresses from registration lists
    // Careful here, will need to re-map any registered autoloops to new indices
    function cleanControllerList() public {}

    function cleanAutoLoopList() public {}

    // Registrar
    function registerAutoLoop(
        address registrantAddress,
        address adminAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        // Will be pre-verified by registrar to prevent duplicate registrations
        isRegisteredAutoLoop[registrantAddress] = true;
        if (!wasRegisteredAutoLoop[registrantAddress]) {
            wasRegisteredAutoLoop[registrantAddress] = true;
            _registeredAutoLoops.push(registrantAddress);
            _registeredAutoLoopIndex[registrantAddress] =
                _registeredAutoLoops.length -
                1;
            _registeredAutoLoopsForAddress[registrantAddress].push(
                _registeredAutoLoopIndex[registrantAddress]
            );
            _setNewAdmin(registrantAddress, adminAddress);
        }
        emit AutoLoopRegistered(registrantAddress, msg.sender, block.timestamp);
    }

    function deregisterAutoLoop(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        if (isRegisteredAutoLoop[registrantAddress]) {
            isRegisteredAutoLoop[registrantAddress] = false;
            // delete _registeredAutoLoops[
            //     _registeredAutoLoopIndex[registrantAddress]
            // ];
            // delete _registeredAutoLoopIndex[registrantAddress];
            emit AutoLoopDeregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }

    function registerController(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        isRegisteredController[registrantAddress] = true;
        if (!wasRegisteredController[registrantAddress]) {
            wasRegisteredController[registrantAddress] = true;
            _registeredControllers.push(registrantAddress);
            _registeredControllerIndex[registrantAddress] =
                _registeredControllers.length -
                1;
        }
        emit ControllerRegistered(
            registrantAddress,
            msg.sender,
            block.timestamp
        );
    }

    function deregisterController(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        if (isRegisteredController[registrantAddress]) {
            isRegisteredController[registrantAddress] = false;
            // delete _registeredControllers[
            //     _registeredControllerIndex[registrantAddress]
            // ];
            // delete _registeredControllerIndex[registrantAddress];
            emit ControllerDeregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }

    function setNewAdmin(
        address autoLoopCompatibleContract,
        address adminAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        _setNewAdmin(autoLoopCompatibleContract, adminAddress);
    }

    function _setNewAdmin(
        address autoLoopCompatibleContract,
        address adminAddress
    ) internal {
        uint256 autoLoopIndex = _registeredAutoLoopIndex[
            autoLoopCompatibleContract
        ];
        uint256[] memory existingRegistrations = _registeredAutoLoopsForAddress[
            adminAddress
        ];
        bool registrationExists;
        for (uint256 i = 0; i < existingRegistrations.length; i++) {
            if (
                _registeredAutoLoops[existingRegistrations[i]] ==
                autoLoopCompatibleContract
            ) {
                // already in registered list
                registrationExists = true;
                break;
            }
        }
        if (!registrationExists) {
            _registeredAutoLoopsForAddress[adminAddress].push(autoLoopIndex);
        }
    }
}

// File contracts/AutoLoopRegistrar.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract AutoLoopRegistrar is AutoLoopRoles {
    AutoLoop AUTO_LOOP;
    AutoLoopRegistry REGISTRY;

    constructor(
        address autoLoopAddress,
        address registryAddress,
        address adminAddress
    ) {
        AUTO_LOOP = AutoLoop(autoLoopAddress);
        REGISTRY = AutoLoopRegistry(registryAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    // IN PROGRESS
    // Draft functions:
    function deposit(address registeredContract) external payable {
        require(msg.value > 0, "no value deposited");
        require(
            REGISTRY.isRegisteredAutoLoop(registeredContract),
            "cannot deposit to unregistered contract"
        );
        AUTO_LOOP.deposit{value: msg.value}(registeredContract);
    }

    function requestRefund(address toAddress) external {
        // controller or contract
        AUTO_LOOP.requestRefund(msg.sender, toAddress);
    }

    function requestRefundFor(
        address registeredContract,
        address toAddress
    ) external {
        require(
            _isAdmin(msg.sender, registeredContract),
            "Cannot request refund. Caller is not admin on contract."
        );
        AUTO_LOOP.requestRefund(registeredContract, toAddress);
    }

    function registerSafeTransfer(
        address autoLoopCompatibleContract,
        address newAdminAddress
    ) external {
        require(
            _isAdmin(msg.sender, autoLoopCompatibleContract),
            "Cannot set gas, caller is not admin on contract"
        );
        REGISTRY.setNewAdmin(autoLoopCompatibleContract, newAdminAddress);
    }

    function setMaxGas(uint256 maxGasPerUpdate) external {
        require(
            REGISTRY.isRegisteredAutoLoop(msg.sender),
            "cannot set max gas on unregistered contract"
        );
        AUTO_LOOP.setMaxGas(msg.sender, maxGasPerUpdate);
    }

    function setMaxGasFor(
        address registeredContract,
        uint256 maxGasPerUpdate
    ) external {
        require(
            _isAdmin(msg.sender, registeredContract),
            "Cannot set gas, caller is not admin on contract"
        );
        require(
            REGISTRY.isRegisteredAutoLoop(registeredContract),
            "cannot set max gas on unregistered contract"
        );
        AUTO_LOOP.setMaxGas(registeredContract, maxGasPerUpdate);
    }

    /**
     * @notice check if a contract can be registered
     * @param registrantAddress the address that will register the contract (address of the contract if self-registering)
     * @param autoLoopCompatibleContract the AutoLoop compatible contract to be registered
     * @return canRegister - whether or not the contract can be registered
     */
    function canRegisterAutoLoop(
        address registrantAddress,
        address autoLoopCompatibleContract
    ) public view returns (bool canRegister) {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredAutoLoop(autoLoopCompatibleContract)) {
            // already registered
            return false;
        } else if (registrantAddress != autoLoopCompatibleContract) {
            // check if registrant is admin on contract
            return _isAdmin(registrantAddress, autoLoopCompatibleContract);
        } else {
            return true;
        }
    }

    /**
     * @notice check if a controller can be registered
     * @param registrantAddress the address of the controller to be registered
     * @return canRegister - whether or not the controller can be registered
     */
    function canRegisterController(
        address registrantAddress
    ) public view returns (bool canRegister) {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredController(registrantAddress)) {
            // already registered
            return false;
        } else {
            return true;
        }
    }

    /**
     * @notice AutoLoop compatible contract registers itself. ACCs can have multiple admins, admin at 0 is indexed.
     * @return success - whether the registration was successful or not
     */
    function registerAutoLoop() external returns (bool success) {
        // pass msg.sender as both arguments since it is both registrant and contract being registered
        if (canRegisterAutoLoop(msg.sender, msg.sender)) {
            address adminAddress = AutoLoopCompatible(msg.sender).getRoleMember(
                DEFAULT_ADMIN_ROLE,
                0
            );
            _registerAutoLoop(msg.sender, adminAddress);
            success = true;
        }
    }

    /**
     * @notice register an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being registered). This will associate this particular admin with this contract instead of the default admin at the first index.
     * @param autoLoopCompatibleContract the address of the contract to register
     * @return success - whether or not the contract was registered
     */
    function registerAutoLoopFor(
        address autoLoopCompatibleContract,
        uint256 maxGasPerUpdate
    ) external payable returns (bool success) {
        if (canRegisterAutoLoop(msg.sender, autoLoopCompatibleContract)) {
            _registerAutoLoop(autoLoopCompatibleContract, msg.sender);
            if (msg.value > 0) {
                AUTO_LOOP.deposit{value: msg.value}(autoLoopCompatibleContract);
            }
            if (maxGasPerUpdate > 0) {
                AUTO_LOOP.setMaxGas(
                    autoLoopCompatibleContract,
                    maxGasPerUpdate
                );
            }
            success = true;
        }
    }

    /**
     * @notice register an AutoLoop controller
     * @return success - whether or not the controller was registered
     */
    function registerController() external returns (bool success) {
        if (canRegisterController(msg.sender)) {
            _registerController(msg.sender);
            success = true;
        }
    }

    /**
     * @notice Claim an AutoLoop contract for UI access. Useful for contracts with multiple admins.
     */
    function claimAutoLoop(address autoLoopCompatibleContract) external {
        require(
            _isAdmin(msg.sender, autoLoopCompatibleContract),
            "Cannot claim contract. Sender is not admin"
        );
        REGISTRY.setNewAdmin(autoLoopCompatibleContract, msg.sender);
    }

    /**
     * @notice AutoLoop compatible contract deregisters itself
     * @return success - whether the unregistration was successful or not
     */
    function deregisterAutoLoop() external returns (bool success) {
        _deregisterAutoLoop(msg.sender);
        success = true;
    }

    /**
     * @notice deregister an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being deregistered)
     * @param autoLoopCompatibleContract the address of the contract to deregister
     * @return success - whether or not the contract was deregistered
     */
    function deregisterAutoLoopFor(
        address autoLoopCompatibleContract
    ) external returns (bool success) {
        if (_isAdmin(msg.sender, autoLoopCompatibleContract)) {
            _deregisterAutoLoop(autoLoopCompatibleContract);
            success = true;
        }
    }

    /**
     * @notice uregister an AutoLoop controller
     */
    function deregisterController() external {
        _deregisterController(msg.sender);
    }

    // internal
    function _isAdmin(
        address testAddress,
        address contractAddress
    ) internal view returns (bool) {
        return
            AutoLoopCompatible(contractAddress).hasRole(
                DEFAULT_ADMIN_ROLE,
                testAddress
            );
    }

    /**
     * @dev registers AutoLoop compatible contract. This should not be called unless a pre-check has been made to verify the contract can be registered.
     */
    function _registerAutoLoop(
        address registrant,
        address adminAddress
    ) internal {
        REGISTRY.registerAutoLoop(registrant, adminAddress);
    }

    /**
     * @dev deregisters AutoLoop compatible contract if possible. No pre-checks are required although they can save gas on a redundant call to deregister.
     */
    function _deregisterAutoLoop(address registrant) internal {
        REGISTRY.deregisterAutoLoop(registrant);
    }

    /**
     * @dev registers controller. This should not be called unless a pre-check has been made to verify the controller can be registered.
     */
    function _registerController(address registrant) internal {
        REGISTRY.registerController(registrant);
        AUTO_LOOP.addController(registrant);
    }

    /**
     * @dev deregisters controller if possible. No pre-checks are required although they can save gas on a redundant call to deregister.
     */
    function _deregisterController(address registrant) internal {
        REGISTRY.deregisterController(registrant);
        AUTO_LOOP.removeController(registrant);
    }
}

// File contracts/sample/NumberGoUp.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// AutoLoopCompatible.sol imports the functions from both @chainlink/contracts/src/v0.8/AutomationBase.sol
// and AutoLoopCompatibleInterface.sol

contract NumberGoUp is AutoLoopCompatible {
    event GameUpdated(uint256 indexed timeStamp);

    uint256 public number;
    uint256 public interval;
    uint256 public lastTimeStamp;

    constructor(uint256 updateInterval) {
        interval = updateInterval;
        lastTimeStamp = block.timestamp;
        number = 0;
    }

    function registerAutoLoop(
        address registrarAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // Register auto loop
        bool success = AutoLoopRegistrar(registrarAddress).registerAutoLoop();
        if (!success) {
            revert("unable to register auto loop");
        }
    }

    function deregisterAutoLoop(
        address registrarAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // Unegister auto loop
        AutoLoopRegistrar(registrarAddress).deregisterAutoLoop();
    }

    // Required functions from AutoLoopCompatibleInterface.sol
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = (block.timestamp - lastTimeStamp) > interval;
        // we pass a loop ID to avoid running the same update twice
        progressWithData = bytes(abi.encode(_loopID));
    }

    function progressLoop(bytes calldata progressWithData) external override {
        // Decode data sent from shouldProgressLoop()
        uint256 loopID = abi.decode(progressWithData, (uint256));
        // Re-check logic from shouldProgressLoop()
        if ((block.timestamp - lastTimeStamp) > interval && loopID == _loopID) {
            updateGame();
        }
    }

    function updateGame() internal {
        // this is what gets called on each auto loop cycle
        emit GameUpdated(block.timestamp);
        lastTimeStamp = block.timestamp;
        ++number;
        ++_loopID;
    }
}
