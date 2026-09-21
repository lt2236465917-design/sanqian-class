function scheduleHtmlParser() {
  // 配置常量
  const CONFIG = {
    APP_BASE: 'https://ehall.seu.edu.cn/jwapp/sys/bykb',
    CURRENT_TERM_API: '/modules/jshkcb/dqxnxq.do',
    TERM_LIST_API: '/modules/jshkcb/xnxqcx.do',
    SCHEDULE_API: '/modules/xskcb/cxxszhxqkb.do',
  };

  const buildUrl = (path) => {
    if (typeof WIS_EMAP_SERV !== 'undefined' && WIS_EMAP_SERV.getAbsPath) {
      return WIS_EMAP_SERV.getAbsPath(path);
    }
    return `${CONFIG.APP_BASE}${path}`;
  };

  const encodeParams = (params = {}) => {
    return Object.keys(params)
      .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
      .join('&');
  };

  // 同步请求，优先使用页面自己的 EMAP Ajax 封装
  const syncRequest = (path, params = {}) => {
    const url = buildUrl(path);

    if (typeof BH_UTILS !== 'undefined' && BH_UTILS.doSyncAjax) {
      return BH_UTILS.doSyncAjax(url, params);
    }

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, false); // 保持同步模式
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.setRequestHeader('Accept', 'application/json, text/javascript, */*; q=0.01');
    xhr.send(encodeParams(params));
    if (xhr.status !== 200) {
      throw new Error(`HTTP Error: ${xhr.status}`);
    }
    return JSON.parse(xhr.responseText);
  };

  // 获取当前学期；若接口异常，回退到学期列表最新项
  const fetchCurrentTerm = () => {
    const data = syncRequest(CONFIG.CURRENT_TERM_API);
    const rows = data?.datas?.dqxnxq?.rows || [];
    if (rows.length > 0) return rows[0];

    const termListData = syncRequest(CONFIG.TERM_LIST_API, { '*order': '-DM' });
    const termRows = termListData?.datas?.xnxqcx?.rows || [];
    return termRows[0];
  };

  // 获取原始课表数据
  const fetchSchedule = (termCode) => {
    const data = syncRequest(CONFIG.SCHEDULE_API, {
      '*order': '+KSJC,+JSJC',
      XNXQDM: termCode,
    });
    return data?.datas?.cxxszhxqkb?.rows || [];
  };

  // 解析周次（优先使用bitmap，回退到文本解析）
  const parseWeeks = (zcmcText, bitMap) => {
    // 方案1：优先使用bitmap（最准确）
    if (typeof bitMap === 'string' && bitMap.length > 0) {
      const weeks = [];
      for (let i = 0; i < bitMap.length; i++) {
        if (bitMap[i] === '1') weeks.push(i + 1);
      }
      if (weeks.length > 0) return weeks;
    }

    // 方案2：解析文本（如"1-8周,9-16周(单)"）
    if (!zcmcText) return [];

    const weekSet = new Set();
    const parts = zcmcText.split(/[，,;；]/);

    parts.forEach(part => {
      const match = part.match(/(\d+)(?:-(\d+))?周?(?:\((单|双)\))?/);
      if (!match) return;

      const start = parseInt(match[1], 10);
      const end = match[2] ? parseInt(match[2], 10) : start;
      const parityFlags = { 单: 1, 双: 2 };
      const parity = parityFlags[match[3]] || 0;

      for (let w = start; w <= end; w++) {
        const isOdd = (w % 2 === 1);
        const shouldInclude =
          parity === 0 ||
          (parity === 1 && isOdd) ||
          (parity === 2 && !isOdd);

        if (shouldInclude) weekSet.add(w);
      }
    });

    return Array.from(weekSet).sort((a, b) => a - b);
  };

  // 转换单条课程数据为目标格式
  const transformCourse = (raw) => {
    const weeks = parseWeeks(raw.ZCMC, raw.SKZC);
    if (weeks.length === 0) return null;

    const weekTime = parseInt(raw.SKXQ, 10);
    const startTime = parseInt(raw.KSJC, 10);
    const endTime = parseInt(raw.JSJC, 10);
    if (!weekTime || !startTime || !endTime || endTime < startTime) return null;

    return {
      name: raw.KCM,
      classroom: raw.JASMC || raw.JASMC_DISPLAY || '',
      class_number: raw.KCH,
      teacher: raw.SKJS,
      test_time: null,
      test_location: null,
      link: null,
      weeks: weeks,
      week_time: weekTime,
      start_time: startTime,
      time_count: endTime - startTime, // 不 +1
      import_type: 1,
      info: raw.ZCMC,
      data: null,
    };
  };

  // 主流程
  try {
    // 步骤1：获取当前学期
    const currentTerm = fetchCurrentTerm();

    if (!currentTerm?.DM) {
      throw new Error('无法获取当前学期信息');
    }

    console.log(`已选择学期：${currentTerm.DM} ${currentTerm.MC}`);

    // 步骤2：获取并转换课表数据
    const rawCourses = fetchSchedule(currentTerm.DM);
    const courses = rawCourses
      .map(transformCourse)
      .filter(course => course !== null); // 过滤无有效周次的课程

    // 步骤3：组装并返回结果
    const result = {
      name: currentTerm.MC,
      courses: courses,
    };

    return encodeURIComponent(JSON.stringify(result));

  } catch (error) {
    console.error('课表解析失败:', error);
    return encodeURIComponent(
      JSON.stringify({
        name: '无法获取学期信息',
        courses: [],
      })
    );
  }
}

scheduleHtmlParser();
