/// Minimal futures executor polyfills.
///
/// This module provides a minimal `block_on` implementation to avoid depending
/// on external executor crates. It is only intended for use in tests and examples.

use std::future::Future;
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
