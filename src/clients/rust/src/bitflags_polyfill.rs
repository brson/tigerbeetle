//! Minimal bitflags implementation for zero-dependency builds.
//!
//! This module provides a bitflags! macro that is API-compatible with
//! the bitflags 2.6 crate, implementing all commonly used methods.

/// A trait for types that represent bitflags.
#[allow(dead_code)]
pub trait Flags: Sized + Copy {
    /// The underlying bits type.
    type Bits: Bits;

    /// Returns the raw bits value.
    fn bits(&self) -> Self::Bits;

    /// Creates a flags value from raw bits, preserving all bits.
    fn from_bits_retain(bits: Self::Bits) -> Self;

    /// Creates a flags value with no bits set.
    fn empty() -> Self {
        Self::from_bits_retain(Self::Bits::EMPTY)
    }

    /// Creates a flags value with all known bits set.
    fn all() -> Self;

    /// Creates a flags value from raw bits, returning None if any unknown bits are set.
    fn from_bits(bits: Self::Bits) -> Option<Self> {
        if bits & !Self::all().bits() == Self::Bits::EMPTY {
            Some(Self::from_bits_retain(bits))
        } else {
            None
        }
    }

    /// Creates a flags value from raw bits, truncating unknown bits.
    fn from_bits_truncate(bits: Self::Bits) -> Self {
        Self::from_bits_retain(bits & Self::all().bits())
    }

    /// Returns true if no flags are set.
    fn is_empty(&self) -> bool {
        self.bits() == Self::Bits::EMPTY
    }

    /// Returns true if all known flags are set.
    fn is_all(&self) -> bool {
        (self.bits() & Self::all().bits()) == Self::all().bits()
    }

    /// Returns true if any flags in `other` are also set in `self`.
    fn intersects(&self, other: Self) -> bool {
        (self.bits() & other.bits()) != Self::Bits::EMPTY
    }

    /// Returns true if all flags in `other` are also set in `self`.
    fn contains(&self, other: Self) -> bool {
        (self.bits() & other.bits()) == other.bits()
    }

    /// Adds the flags in `other` to `self`.
    fn insert(&mut self, other: Self) {
        *self = Self::from_bits_retain(self.bits() | other.bits());
    }

    /// Removes the flags in `other` from `self`.
    fn remove(&mut self, other: Self) {
        *self = Self::from_bits_retain(self.bits() & !other.bits());
    }

    /// Toggles the flags in `other` in `self`.
    fn toggle(&mut self, other: Self) {
        *self = Self::from_bits_retain(self.bits() ^ other.bits());
    }

    /// Sets or unsets the flags in `other` in `self` based on `value`.
    fn set(&mut self, other: Self, value: bool) {
        if value {
            self.insert(other);
        } else {
            self.remove(other);
        }
    }

    /// Returns the intersection of `self` and `other`.
    fn intersection(self, other: Self) -> Self {
        Self::from_bits_retain(self.bits() & other.bits())
    }

    /// Returns the union of `self` and `other`.
    fn union(self, other: Self) -> Self {
        Self::from_bits_retain(self.bits() | other.bits())
    }

    /// Returns the difference of `self` and `other`.
    fn difference(self, other: Self) -> Self {
        Self::from_bits_retain(self.bits() & !other.bits())
    }

    /// Returns the symmetric difference of `self` and `other`.
    fn symmetric_difference(self, other: Self) -> Self {
        Self::from_bits_retain(self.bits() ^ other.bits())
    }

    /// Returns the complement of `self`.
    fn complement(self) -> Self {
        Self::from_bits_truncate(!self.bits())
    }
}

/// Trait for types that can be used as the underlying storage for flags.
pub trait Bits:
    Copy
    + PartialEq
    + std::ops::BitAnd<Output = Self>
    + std::ops::BitOr<Output = Self>
    + std::ops::BitXor<Output = Self>
    + std::ops::Not<Output = Self>
{
    const EMPTY: Self;
}

impl Bits for u8 {
    const EMPTY: Self = 0;
}

impl Bits for u16 {
    const EMPTY: Self = 0;
}

impl Bits for u32 {
    const EMPTY: Self = 0;
}

impl Bits for u64 {
    const EMPTY: Self = 0;
}

impl Bits for u128 {
    const EMPTY: Self = 0;
}

/// Defines a bitflags type.
///
/// This macro is API-compatible with the bitflags 2.6 crate.
macro_rules! bitflags {
    (
        $(#[$outer:meta])*
        $vis:vis struct $name:ident: $repr:ty {
            $(
                $(#[$flag_meta:meta])*
                const $flag:ident = $value:expr;
            )*
        }
    ) => {
        $(#[$outer])*
        $vis struct $name($repr);

        #[allow(non_upper_case_globals)]
        impl $name {
            $(
                $(#[$flag_meta])*
                pub const $flag: Self = Self($value);
            )*

            /// Returns the raw bits value.
            #[inline]
            pub const fn bits(&self) -> $repr {
                self.0
            }

            /// Creates a flags value with no bits set.
            #[inline]
            pub const fn empty() -> Self {
                Self(0)
            }

            /// Creates a flags value with all known bits set.
            #[inline]
            pub const fn all() -> Self {
                Self(0 $(| $value)*)
            }

            /// Creates a flags value from raw bits, returning None if any unknown bits are set.
            #[inline]
            pub fn from_bits(bits: $repr) -> ::core::option::Option<Self> {
                <Self as $crate::bitflags_polyfill::Flags>::from_bits(bits)
            }

            /// Creates a flags value from raw bits, truncating unknown bits.
            #[inline]
            pub const fn from_bits_truncate(bits: $repr) -> Self {
                Self(bits & Self::all().bits())
            }

            /// Creates a flags value from raw bits, preserving all bits.
            #[inline]
            pub const fn from_bits_retain(bits: $repr) -> Self {
                Self(bits)
            }

            /// Returns true if no flags are set.
            #[inline]
            pub const fn is_empty(&self) -> bool {
                self.0 == 0
            }

            /// Returns true if all known flags are set.
            #[inline]
            pub const fn is_all(&self) -> bool {
                (self.0 & Self::all().bits()) == Self::all().bits()
            }

            /// Returns true if any flags in `other` are also set in `self`.
            #[inline]
            pub const fn intersects(&self, other: Self) -> bool {
                (self.0 & other.0) != 0
            }

            /// Returns true if all flags in `other` are also set in `self`.
            #[inline]
            pub const fn contains(&self, other: Self) -> bool {
                (self.0 & other.0) == other.0
            }

            /// Adds the flags in `other` to `self`.
            #[inline]
            pub fn insert(&mut self, other: Self) {
                self.0 |= other.0;
            }

            /// Removes the flags in `other` from `self`.
            #[inline]
            pub fn remove(&mut self, other: Self) {
                self.0 &= !other.0;
            }

            /// Toggles the flags in `other` in `self`.
            #[inline]
            pub fn toggle(&mut self, other: Self) {
                self.0 ^= other.0;
            }

            /// Sets or unsets the flags in `other` in `self` based on `value`.
            #[inline]
            pub fn set(&mut self, other: Self, value: bool) {
                if value {
                    self.insert(other);
                } else {
                    self.remove(other);
                }
            }

            /// Returns the intersection of `self` and `other`.
            #[inline]
            pub const fn intersection(self, other: Self) -> Self {
                Self(self.0 & other.0)
            }

            /// Returns the union of `self` and `other`.
            #[inline]
            pub const fn union(self, other: Self) -> Self {
                Self(self.0 | other.0)
            }

            /// Returns the difference of `self` and `other`.
            #[inline]
            pub const fn difference(self, other: Self) -> Self {
                Self(self.0 & !other.0)
            }

            /// Returns the symmetric difference of `self` and `other`.
            #[inline]
            pub const fn symmetric_difference(self, other: Self) -> Self {
                Self(self.0 ^ other.0)
            }

            /// Returns the complement of `self`.
            #[inline]
            pub const fn complement(self) -> Self {
                Self(!self.0 & Self::all().bits())
            }
        }

        impl $crate::bitflags_polyfill::Flags for $name {
            type Bits = $repr;

            #[inline]
            fn bits(&self) -> Self::Bits {
                self.0
            }

            #[inline]
            fn from_bits_retain(bits: Self::Bits) -> Self {
                Self(bits)
            }

            #[inline]
            fn all() -> Self {
                Self(0 $(| $value)*)
            }
        }

        impl ::core::fmt::Binary for $name {
            fn fmt(&self, f: &mut ::core::fmt::Formatter) -> ::core::fmt::Result {
                ::core::fmt::Binary::fmt(&self.0, f)
            }
        }

        impl ::core::fmt::Octal for $name {
            fn fmt(&self, f: &mut ::core::fmt::Formatter) -> ::core::fmt::Result {
                ::core::fmt::Octal::fmt(&self.0, f)
            }
        }

        impl ::core::fmt::LowerHex for $name {
            fn fmt(&self, f: &mut ::core::fmt::Formatter) -> ::core::fmt::Result {
                ::core::fmt::LowerHex::fmt(&self.0, f)
            }
        }

        impl ::core::fmt::UpperHex for $name {
            fn fmt(&self, f: &mut ::core::fmt::Formatter) -> ::core::fmt::Result {
                ::core::fmt::UpperHex::fmt(&self.0, f)
            }
        }

        impl ::core::ops::BitOr for $name {
            type Output = Self;

            #[inline]
            fn bitor(self, other: Self) -> Self {
                <Self as $crate::bitflags_polyfill::Flags>::union(self, other)
            }
        }

        impl ::core::ops::BitOrAssign for $name {
            #[inline]
            fn bitor_assign(&mut self, other: Self) {
                <Self as $crate::bitflags_polyfill::Flags>::insert(self, other);
            }
        }

        impl ::core::ops::BitAnd for $name {
            type Output = Self;

            #[inline]
            fn bitand(self, other: Self) -> Self {
                <Self as $crate::bitflags_polyfill::Flags>::intersection(self, other)
            }
        }

        impl ::core::ops::BitAndAssign for $name {
            #[inline]
            fn bitand_assign(&mut self, other: Self) {
                *self = <Self as $crate::bitflags_polyfill::Flags>::intersection(*self, other);
            }
        }

        impl ::core::ops::BitXor for $name {
            type Output = Self;

            #[inline]
            fn bitxor(self, other: Self) -> Self {
                <Self as $crate::bitflags_polyfill::Flags>::symmetric_difference(self, other)
            }
        }

        impl ::core::ops::BitXorAssign for $name {
            #[inline]
            fn bitxor_assign(&mut self, other: Self) {
                <Self as $crate::bitflags_polyfill::Flags>::toggle(self, other);
            }
        }

        impl ::core::ops::Sub for $name {
            type Output = Self;

            #[inline]
            fn sub(self, other: Self) -> Self {
                <Self as $crate::bitflags_polyfill::Flags>::difference(self, other)
            }
        }

        impl ::core::ops::SubAssign for $name {
            #[inline]
            fn sub_assign(&mut self, other: Self) {
                <Self as $crate::bitflags_polyfill::Flags>::remove(self, other);
            }
        }

        impl ::core::ops::Not for $name {
            type Output = Self;

            #[inline]
            fn not(self) -> Self {
                <Self as $crate::bitflags_polyfill::Flags>::complement(self)
            }
        }

        impl ::core::iter::Extend<$name> for $name {
            fn extend<T: ::core::iter::IntoIterator<Item = $name>>(&mut self, iterator: T) {
                for item in iterator {
                    <Self as $crate::bitflags_polyfill::Flags>::insert(self, item);
                }
            }
        }

        impl ::core::iter::FromIterator<$name> for $name {
            fn from_iter<T: ::core::iter::IntoIterator<Item = $name>>(iterator: T) -> Self {
                let mut result = <Self as $crate::bitflags_polyfill::Flags>::empty();
                result.extend(iterator);
                result
            }
        }
    };
}

pub(crate) use bitflags;
