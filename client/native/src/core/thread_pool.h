#ifndef SEEKER_THREAD_POOL_H
#define SEEKER_THREAD_POOL_H

#include <condition_variable>
#include <functional>
#include <future>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace seeker {

/// 简单线程池，用于异步执行流提取等任务
class ThreadPool {
public:
    explicit ThreadPool(size_t num_threads = 4);
    ~ThreadPool();

    /// 提交任务到线程池
    template<class F>
    auto submit(F&& f) -> std::future<decltype(f())>;

    /// 停止线程池（等待所有任务完成）
    void shutdown();

    // 禁止拷贝
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;

private:
    std::vector<std::thread> workers_;
    std::queue<std::function<void()>> tasks_;
    std::mutex queue_mutex_;
    std::condition_variable condition_;
    bool stop_{false};
};

// 模板实现
template<class F>
auto ThreadPool::submit(F&& f) -> std::future<decltype(f())> {
    using ReturnType = decltype(f());
    auto task = std::make_shared<std::packaged_task<ReturnType()>>(std::forward<F>(f));
    std::future<ReturnType> result = task->get_future();
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        tasks_.emplace([task]() { (*task)(); });
    }
    condition_.notify_one();
    return result;
}

} // namespace seeker

#endif // SEEKER_THREAD_POOL_H
