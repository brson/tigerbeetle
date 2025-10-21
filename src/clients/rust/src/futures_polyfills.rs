//! Minimal polyfills for futures functionality.
//!
//! This module provides minimal implementations of futures utilities to avoid
//! dependencies on futures-executor and futures-util, which have transitive
//! dependencies on `syn`, which has a high MSRV.
//!
//! These are only used in tests.

use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};
use std::thread;

pub use futures_core::Stream;

pub mod executor {
    pub use super::block_on;
}

pub mod stream {
    pub use super::{unfold, StreamExt};
}

pub fn block_on<F: Future>(mut future: F) -> F::Output {
    let mut future = unsafe { Pin::new_unchecked(&mut future) };

    static VTABLE: RawWakerVTable = RawWakerVTable::new(
        |_| RawWaker::new(std::ptr::null(), &VTABLE),
        |_| {},
        |_| {},
        |_| {},
    );

    let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
    let mut context = Context::from_waker(&waker);

    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(output) => return output,
            Poll::Pending => thread::yield_now(),
        }
    }
}

enum UnfoldState<T, R> {
    Value { value: T },
    Future { future: R },
    Empty,
}

impl<T, R> UnfoldState<T, R> {
    /// Projects a pinned reference to the future if in Future state.
    fn project_future(self: Pin<&mut Self>) -> Option<Pin<&mut R>> {
        unsafe {
            match self.get_unchecked_mut() {
                UnfoldState::Future { future } => Some(Pin::new_unchecked(future)),
                _ => None,
            }
        }
    }

    /// Takes the value if in Value state, replacing with Empty.
    fn take_value(self: Pin<&mut Self>) -> Option<T> {
        unsafe {
            let this = self.get_unchecked_mut();
            match this {
                UnfoldState::Value { .. } => {
                    match std::mem::replace(this, UnfoldState::Empty) {
                        UnfoldState::Value { value } => Some(value),
                        _ => unreachable!(),
                    }
                }
                _ => None,
            }
        }
    }
}

#[must_use = "streams do nothing unless polled"]
pub struct Unfold<T, F, Fut> {
    f: F,
    state: UnfoldState<T, Fut>,
}

impl<T, F, Fut, Item> futures_core::Stream for Unfold<T, F, Fut>
where
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Option<(Item, T)>>,
{
    type Item = Item;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        unsafe {
            let this = self.get_unchecked_mut();
            let mut state = Pin::new_unchecked(&mut this.state);

            if let Some(value) = state.as_mut().take_value() {
                let future = (this.f)(value);
                *Pin::into_inner_unchecked(state) = UnfoldState::Future { future };
            }

            let state = Pin::new_unchecked(&mut this.state);
            let step = match state.project_future() {
                Some(fut) => match fut.poll(cx) {
                    Poll::Ready(result) => result,
                    Poll::Pending => return Poll::Pending,
                },
                None => panic!("Unfold must not be polled after it returned Poll::Ready(None)"),
            };

            if let Some((item, next_state)) = step {
                *Pin::into_inner_unchecked(Pin::new_unchecked(&mut this.state)) =
                    UnfoldState::Value { value: next_state };
                Poll::Ready(Some(item))
            } else {
                *Pin::into_inner_unchecked(Pin::new_unchecked(&mut this.state)) =
                    UnfoldState::Empty;
                Poll::Ready(None)
            }
        }
    }
}

pub fn unfold<T, F, Fut, Item>(init: T, f: F) -> Unfold<T, F, Fut>
where
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Option<(Item, T)>>,
{
    Unfold {
        f,
        state: UnfoldState::Value { value: init },
    }
}

pub trait StreamExt: Stream {
    fn next(&mut self) -> Next<'_, Self>
    where
        Self: Unpin,
    {
        Next { stream: self }
    }
}

impl<T: Stream + ?Sized> StreamExt for T {}

pub struct Next<'a, S: ?Sized> {
    stream: &'a mut S,
}

impl<S: Stream + Unpin + ?Sized> Future for Next<'_, S> {
    type Output = Option<S::Item>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        Pin::new(&mut *self.stream).poll_next(cx)
    }
}

#[macro_export]
macro_rules! tb_pin_mut {
    ($($x:ident),* $(,)?) => {
        $(
            let mut $x = $x;
            #[allow(unused_mut)]
            let mut $x = unsafe {
                std::pin::Pin::new_unchecked(&mut $x)
            };
        )*
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_channel::oneshot;

    #[test]
    fn test_block_on_immediate() {
        async fn immediate() -> i32 {
            42
        }

        let result = block_on(immediate());
        assert_eq!(result, 42);
    }

    #[test]
    fn test_block_on_nested() {
        async fn nested() -> String {
            async fn inner() -> &'static str {
                "hello"
            }
            let s = inner().await;
            format!("{} world", s)
        }

        let result = block_on(nested());
        assert_eq!(result, "hello world");
    }

    #[test]
    fn test_block_on_with_oneshot() {
        let (tx, rx) = oneshot::channel();

        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(10));
            tx.send(123).unwrap();
        });

        let result = block_on(async { rx.await.unwrap() });
        assert_eq!(result, 123);
    }

    #[test]
    fn test_unfold_simple_sequence() {
        let stream = unfold(0, |state| async move {
            if state < 3 {
                Some((state * 2, state + 1))
            } else {
                None
            }
        });

        let mut stream = Box::pin(stream);
        let mut results = Vec::new();

        loop {
            match block_on(async {
                let pinned = Pin::new(&mut stream);
                futures_core::Stream::poll_next(pinned, &mut Context::from_waker(&noop_waker()))
            }) {
                Poll::Ready(Some(item)) => results.push(item),
                Poll::Ready(None) => break,
                Poll::Pending => continue,
            }
        }

        assert_eq!(results, vec![0, 2, 4]);
    }

    #[test]
    fn test_unfold_empty_stream() {
        let stream = unfold((), |_| async move { None::<(i32, ())> });

        let mut stream = Box::pin(stream);

        let result = block_on(async {
            let pinned = Pin::new(&mut stream);
            futures_core::Stream::poll_next(pinned, &mut Context::from_waker(&noop_waker()))
        });

        assert!(matches!(result, Poll::Ready(None)));
    }

    #[test]
    fn test_unfold_state_mutation() {
        let stream = unfold(vec![1, 2, 3], |mut vec| async move {
            vec.pop().map(|item| (item, vec))
        });

        let mut stream = Box::pin(stream);
        let mut results = Vec::new();

        loop {
            match block_on(async {
                let pinned = Pin::new(&mut stream);
                futures_core::Stream::poll_next(pinned, &mut Context::from_waker(&noop_waker()))
            }) {
                Poll::Ready(Some(item)) => results.push(item),
                Poll::Ready(None) => break,
                Poll::Pending => continue,
            }
        }

        assert_eq!(results, vec![3, 2, 1]);
    }

    #[test]
    fn test_unfold_async_computation() {
        let stream = unfold(0, |state| async move {
            if state < 5 {
                let (tx, rx) = oneshot::channel();
                std::thread::spawn(move || {
                    tx.send(state).unwrap();
                });
                let value = rx.await.unwrap();
                Some((value * value, state + 1))
            } else {
                None
            }
        });

        let mut stream = Box::pin(stream);
        let mut results = Vec::new();

        loop {
            match block_on(async {
                let pinned = Pin::new(&mut stream);
                futures_core::Stream::poll_next(pinned, &mut Context::from_waker(&noop_waker()))
            }) {
                Poll::Ready(Some(item)) => results.push(item),
                Poll::Ready(None) => break,
                Poll::Pending => continue,
            }
        }

        assert_eq!(results, vec![0, 1, 4, 9, 16]);
    }

    fn noop_waker() -> Waker {
        static VTABLE: RawWakerVTable = RawWakerVTable::new(
            |_| RawWaker::new(std::ptr::null(), &VTABLE),
            |_| {},
            |_| {},
            |_| {},
        );
        unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) }
    }
}
