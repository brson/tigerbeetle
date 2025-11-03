/// Minimal futures executor polyfills.
///
/// This module provides minimal implementations of common futures utilities to
/// avoid depending on external executor crates. It is primarily intended for
/// use in tests and examples.
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Condvar, Mutex};
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

/// Runs a future to completion on the current thread.
///
/// This blocks the current thread until the future completes. The implementation
/// uses a simple park/unpark mechanism with a condition variable.
pub fn block_on<F: Future>(future: F) -> F::Output {
    let mut future = Box::pin(future);

    let parker = Arc::new(Parker::new());
    let waker = parker_into_waker(parker.clone());
    let mut context = Context::from_waker(&waker);

    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(result) => return result,
            Poll::Pending => parker.park(),
        }
    }
}

struct Parker {
    mutex: Mutex<bool>,
    condvar: Condvar,
}

impl Parker {
    fn new() -> Self {
        Parker {
            mutex: Mutex::new(false),
            condvar: Condvar::new(),
        }
    }

    fn unpark(&self) {
        let mut notified = self.mutex.lock().unwrap();
        *notified = true;
        self.condvar.notify_one();
    }

    fn park(&self) {
        let mut notified = self.mutex.lock().unwrap();
        while !*notified {
            notified = self.condvar.wait(notified).unwrap();
        }
        *notified = false;
    }
}

fn parker_into_waker(parker: Arc<Parker>) -> Waker {
    let raw_waker = parker_into_raw_waker(parker);
    unsafe { Waker::from_raw(raw_waker) }
}

fn parker_into_raw_waker(parker: Arc<Parker>) -> RawWaker {
    RawWaker::new(Arc::into_raw(parker) as *const (), &VTABLE)
}

const VTABLE: RawWakerVTable = RawWakerVTable::new(clone, wake, wake_by_ref, drop);

unsafe fn clone(ptr: *const ()) -> RawWaker {
    let parker = Arc::from_raw(ptr as *const Parker);
    let cloned = parker.clone();
    let _ = Arc::into_raw(parker);
    parker_into_raw_waker(cloned)
}

unsafe fn wake(ptr: *const ()) {
    let parker = Arc::from_raw(ptr as *const Parker);
    parker.unpark();
}

unsafe fn wake_by_ref(ptr: *const ()) {
    let parker = Arc::from_raw(ptr as *const Parker);
    parker.unpark();
    let _ = Arc::into_raw(parker);
}

unsafe fn drop(ptr: *const ()) {
    let _ = Arc::from_raw(ptr as *const Parker);
}

/// A minimal Stream trait.
///
/// This trait is a subset of the futures-util Stream trait, providing only the
/// functionality needed for TigerBeetle client tests.
pub trait Stream {
    /// The type of items yielded by the stream.
    type Item;

    /// Attempt to pull out the next value of this stream.
    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>>;
}

/// Extension methods for Stream.
pub trait StreamExt: Stream {
    /// Advances the stream and returns the next value.
    fn next(&mut self) -> Next<'_, Self>
    where
        Self: Unpin,
    {
        Next { stream: self }
    }
}

impl<T: Stream + ?Sized> StreamExt for T {}

/// Future for the `next` method.
pub struct Next<'a, S: ?Sized> {
    stream: &'a mut S,
}

impl<S: Stream + Unpin + ?Sized> Future for Next<'_, S> {
    type Output = Option<S::Item>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        Pin::new(&mut *self.stream).poll_next(cx)
    }
}

/// Creates a stream from a seed value and a closure.
///
/// This is a simplified version of futures-util's stream::unfold.
pub fn unfold<T, F, Fut, Item>(init: T, f: F) -> Unfold<T, F, Fut>
where
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Option<(Item, T)>>,
{
    Unfold {
        state: Some(init),
        f,
        fut: None,
    }
}

/// Stream for the `unfold` function.
pub struct Unfold<T, F, Fut> {
    state: Option<T>,
    f: F,
    fut: Option<Fut>,
}

impl<T, F, Fut> Unpin for Unfold<T, F, Fut> {}

impl<T, F, Fut, Item> Stream for Unfold<T, F, Fut>
where
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Option<(Item, T)>>,
{
    type Item = Item;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        // SAFETY: We never move out of the pinned fields.
        let this = unsafe { self.get_unchecked_mut() };

        loop {
            if let Some(fut) = &mut this.fut {
                // SAFETY: We're pinning the future in place.
                let fut = unsafe { Pin::new_unchecked(fut) };
                match fut.poll(cx) {
                    Poll::Ready(Some((item, next_state))) => {
                        this.fut = None;
                        this.state = Some(next_state);
                        return Poll::Ready(Some(item));
                    }
                    Poll::Ready(None) => {
                        this.fut = None;
                        this.state = None;
                        return Poll::Ready(None);
                    }
                    Poll::Pending => return Poll::Pending,
                }
            }

            if let Some(state) = this.state.take() {
                this.fut = Some((this.f)(state));
            } else {
                return Poll::Ready(None);
            }
        }
    }
}

/// Pins a value on the stack.
///
/// This is a simplified version of the `pin_mut!` macro from futures-util.
#[macro_export]
macro_rules! pin_mut {
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
