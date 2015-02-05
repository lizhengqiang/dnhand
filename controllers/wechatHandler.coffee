_       = require('lodash')
Then    = require('thenjs')
wechat  = require('wechat')
logger  = require('winston')
urllib  = require('urllib')
cheerio = require('cheerio')
iconv   = require("iconv-lite")
moment  = require('moment')
moment.locale('zh-cn')

cons = require('../lib/constants')
wechatApi = require('../lib/wechatApi')
logger = console

OpenIdService   = require '../service/OpenId'
GradeService    = require '../service/Grade'
StudentService  = require '../service/Student'
SyllabusService = require '../service/Syllabus'

class ImageText
  constructor: (@title, @description = '', @url = '', @picurl = '') ->

wechatApiCallback = (err, result) ->
  if err
    console.log err

module.exports = wechat.text((info, req, res) ->
  # 处理存在预先状态的消息
  if req.wxsession and req.wxsession.hasStatus
    dealWithStatus req, res
    return

  key = info.Content
  switch
    when key is '绑定'
      title = "东农助手"
      desc = """
            请点击本消息绑定学号
            """
      url = "http://n.feit.me/bind?openid=#{info.FromUserName}"
      logoUrl = "http://n.feit.me/public/dnhandlogo.jpg"
      imageTextItem = new ImageText(title, desc, url, logoUrl)
      res.reply([imageTextItem])

    when /.*(课|课程)表/.test key
      info.day = switch
        when !!~ key.indexOf '今'   then 0
        when !!~ key.indexOf '明'   then 1
        when !!~ key.indexOf '大后'  then 3
        when !!~ key.indexOf '后'   then 2
        when !!~ key.indexOf '昨'   then -1
        when !!~ key.indexOf '大前'  then -3
        when !!~ key.indexOf '前'   then -2

      if info.day? then getSyllabusByDay info, res else getAllSyllabus info, res

    when /.*(成绩|分数)/.test key
      switch
        when !!~ key.indexOf '本学期'
          getNowGrade info, res
        when !!~ key.indexOf '不及格'
          getNoPassGrade info, res
        when /.*(四|六|四六)级/.test key
          getCetGrade info, res
        else
          getAllGrade info, res

    when /^补考.*/.test key
      if key is '补考'
        return res.reply """
          请回复补考+学号查询
          例：补考A19120626
          """
      stuid = info.Content.substring(2)
      process.nextTick () ->
        getMakeUpExamInfo stuid, info.FromUserName
      res.reply '正在查询补考信息...'

    when /^期末.*/.test key
      if key is '期末'
        return res.reply """
          请回复期末+学号查询
          例：期末A19120626
          """
      stuid = info.Content.substring(2)
      process.nextTick () ->
        getTermEndExamInfo stuid, info.FromUserName
      res.reply '正在查询期末考试信息...'

    when key is '准考证'
      res.reply """
        请回复身份证号查询四六级准考证
        仅限农大同学
        """

    when key.length is 18
      url = "http://202.118.167.91/bm/cetzkz/images/#{key}.jpg"
      title = "四六级级准考证"
      description = """
        请点击查看你的准考证
        如果没有看到准考证图片
        请检查并重新回复身份证号
        """
      return res.reply([new ImageText(title, description, url, url)])

    when key is '更新'
      res.reply()
      updateUserInfo(info)

    when key is 'kf'
      res.reply('正在发送客服消息')
      wechatApi.sendText info.FromUserName, '客服消息', wechatApiCallback

    when key is '客服'
      if wechatApi.canThis
        wechatApi.sendText info.FromUserName, '随便问~', wechatApiCallback
      res.transfer2CustomerService('feit')

    else
      replyUsage info, res

).event((info, req, res) ->
  switch info.Event
    when 'CLICK'

      switch info.EventKey
        when 'todaysyllabus'
          getSyllabusByDay info, res

        when 'tomorrowsyllabus'
          info.day = 1
          getSyllabusByDay info, res

        when 'allsyllabus'
          getAllSyllabus info, res

        when 'nowgrade'
          getNowGrade info, res

        when 'bjggrade'
          getNoPassGrade info, res

        when 'allgrade'
          getAllGrade info, res

        when 'exam'
          res.reply """
          查询期末考试安排
          请回复期末+学号查询
          例：期末A19120000

          查询补考信息
          请回复补考+学号查询
          例：补考A19120000

          查询四六级准考证
          请回复身份证号查询四六级准考证
          仅限农大同学
          """

        when 'updateinfo'
          res.reply()
          updateUserInfo(info)
        else
          replyUsage info, res

    when 'subscribe'
      replyUsage info, res

    when 'unsubscribe'
      res.reply()

    else
      replyUsage info, res

)

replyUsage = (info, res) ->
  openid = info.FromUserName
  Then (cont) ->
    OpenIdService.getUser openid, 'stuid nickname', cont
  .then (cont, user) ->
    its = [new ImageText('             如何优雅的使用')]
    its.push new ImageText(cons.subscribe(name: user.nickname))
    unless user.stuid
      its.push new ImageText('   欢迎关注，点我绑定账户', '', "http://n.feit.me/bind?openid=#{openid}")
    res.reply its

getAllSyllabus = (info, res) ->
  if wechatApi.canThis
    Then (cont) ->
      OpenIdService.getUser info.FromUserName, 'stuid', cont

    .then (cont, user) ->
      unless user.stuid
        return res.reply '查询课表需先绑定账户\n   请回复"绑定"'

      SyllabusService.get user.stuid, null, cont

    .then (cont, syllabus) ->

      unless syllabus
        return res.reply "您的信息已过期，请回复“更新”，获取最新信息"

      res.reply("正在查询...")
      syllabuses = []
      for i in [0...7]
        syllabuses.push _formatSyllabus(i, syllabus[i])

      interval = 500
      startTime = -500
      syllabuses.forEach (syllabusItem) ->
        startTime += interval
        sendNews = () -> wechatApi.sendNews(info.FromUserName, syllabusItem, cont)
        setTimeout(sendNews, startTime)

    .fail (cont, err) ->
      logger.trace err

  else
    res.reply '未取得高级接口权限，不能进行此操作'

getSyllabusByDay = (info, res) ->
  Then (cont) ->
    OpenIdService.getUser info.FromUserName, 'stuid', cont

  .then (cont, user) ->
    unless user.stuid
      return res.reply '查询课表需先绑定账户\n   请回复"绑定"'

    info.day = if info.day
      absDay = (moment().day() + info.day) % 7
      absDay = 7 + absDay if absDay < 0
      absDay
    else
      moment().day()

    return res.reply '星期天休息，亲' if info.day is 0

    SyllabusService.get user.stuid, "#{info.day}", cont

  .then (cont, syllabus) ->
    unless syllabus
      return res.reply "您的信息已过期，请回复“更新”，获取最新信息"

    syllabus = syllabus[info.day]
    res.reply _formatSyllabus(info.day, syllabus)

  .fail (cont, err) ->
    logger.trace err

_formatSyllabus = (day, syllabus) ->
  if day is 0
    weekday = '                 未分配时间'
  else
    weekday = "                    星期#{_transferNumDayToChinese(day)}"
  result = [new ImageText weekday]

  for num, courseArray of syllabus
    numStr = "第#{_transferNumDayToChinese(num)}节"
    for course in courseArray
      courseStr = """
        #{numStr}：#{course.name}
        教室： #{course.building}:#{course.room}
        任课教师： #{course.teacher}   学分：#{course.credit}
        上课周次：  #{course.week}
        """
      result.push new ImageText courseStr

  if result.length is 1
    result.push(new ImageText("                             无！"))

  result.push(new ImageText("            本周为第#{moment().week() - 36}周(仅供参考)"))
  return result

_transferNumDayToChinese = (day) ->
  switch String(day)
    when '1' then '一'
    when '2' then '二'
    when '3' then '三'
    when '4' then '四'
    when '5' then '五'
    when '6' then '六'
    when '7' then '日'

getAllGrade = (info, res) ->
  process.nextTick ->
    updateUserInfo(info)
  title = "东农助手"
  desc = """
        请点击本消息查看全部成绩
        """
  url = "http://n.feit.me/info/allgrade?openid=#{info.FromUserName}"
  logoUrl = "http://n.feit.me/public/dnhandlogo.jpg"
  imageTextItem = new ImageText(title, desc, url, logoUrl)
  res.reply([imageTextItem])

getNowGrade = (info, res) ->
  process.nextTick ->
    updateUserInfo(info)
  Then (cont) ->
    OpenIdService.getUser info.FromUserName, 'stuid', cont

  .then (cont, user) ->
    unless user.stuid
      return res.reply '查询成绩需先绑定账户\n   请回复"绑定"'

    info.stuid = user.stuid
    GradeService.get user.stuid, 'qb', cont

  .then (cont, grade) ->
    unless grade
      return res.reply "您的信息已过期，请回复“更新”，获取最新信息"

    result = grade['qb']['2014-2015学年秋(两学期)']
    if not result or result.length is 0
      return res.reply('暂时还没有上学期成绩信息')

    gradeStr = ["学号：#{info.stuid}\n\n"]
    for item in result
      gradeStr.push("#{item.kcm}\n")
      gradeStr.push("成绩：#{item.cj}\n")
      gradeStr.push("------------------\n")
    gradeStr.push("仅显示及格科目成绩！")
    res.reply gradeStr.join('')

  .fail (cont, err) ->
    logger.trace err

getNoPassGrade = (info, res) ->
  process.nextTick ->
    updateUserInfo(info)
  Then (cont) ->
    OpenIdService.getUser info.FromUserName, 'stuid', cont

  .then (cont, user) ->
    unless user.stuid
      return res.reply '查询成绩需先绑定账户\n   请回复"绑定"'

    info.stuid = user.stuid
    GradeService.get user.stuid, 'bjg', cont

  .then (cont, grade) ->
    unless grade
      return res.reply "您的信息已过期，请回复“更新”，获取最新信息"

    gradeStr = ["学号：#{info.stuid}\n\n"]
    now = grade['bjg']['尚不及格']
    gradeStr.push '--尚不及格--\n'
    if not now or now.length is 0
      gradeStr.push '没有尚不及格科目'
    else
      for item in now
        gradeStr.push("#{item.kcm}\n")
        gradeStr.push("成绩：#{item.cj}\n")
        gradeStr.push("学分：#{item.xf}\n")
        gradeStr.push("考试时间：#{item.kssj}\n")
        gradeStr.push("------------------\n")

    ever = grade['bjg']['曾不及格']
    gradeStr.push '\n--曾不及格--\n'
    if not ever or ever.length is 0
      gradeStr.push '没有曾不及格科目'
    else
      for item in ever
        gradeStr.push("#{item.kcm}\n")
        gradeStr.push("成绩：#{item.cj}\n")
        gradeStr.push("学分：#{item.xf}\n")
        gradeStr.push("考试时间：#{item.kssj}\n")
        gradeStr.push("------------------\n")

    res.reply gradeStr.join('')

  .fail (cont, err) ->
    logger.trace err

updateUserInfo = (info) ->
  openid = info.FromUserName
  Then (cont) ->
    OpenIdService.getUser openid, 'stuid', cont

  .then (cont, user) ->
    unless user.stuid
      if wechatApi.canThis
        wechatApi.sendText openid, "<a href=\"http://n.feit.me/bind?openid=#{openid}\">点我去绑定账户</a>", wechatApiCallback
        return

    StudentService.get user.stuid, null, cont

  .then (cont, studentInfo) ->
    if studentInfo.is_pswd_invalid
      openid = openid
      if wechatApi.canThis
        wechatApi.sendText openid, "您的身份信息已过期，\n<a href=\"http://n.feit.me/bind?openid=#{openid}\">点我去绑定账户</a>", wechatApiCallback
        return
    else
      if wechatApi.canThis
        wechatApi.sendText openid, '正在更新信息...', wechatApiCallback
      student = new StudentService(studentInfo.stuid, studentInfo.pswd)
      student.hasBind = true

      Then (cont1) ->
        student.login cont1
      .then (cont1, result) ->
        student.getInfoAndSave cont
      .fail (cont1, err) ->
        cont err

  .then (cont) ->
    if wechatApi.canThis
      wechatApi.sendText openid, '您的信息更新成功。', wechatApiCallback
  .fail (cont, err) ->
    if err.name isnt 'loginerror'
      logger.trace err
    if wechatApi.canThis
      wechatApi.sendText openid, "您的信息更新失败。\n<a href=\"http://n.feit.me/bind?openid=#{openid}\">点我去网页更新</a>", wechatApiCallback

getCetGrade: (cetNum, name, res) ->
  cetGradeUrl = "http://www.chsi.com.cn/cet/query?zkzh=#{cetNum}&xm=#{encodeURIComponent(name)}"
  opts =
    dataType: 'text'
    headers:
      'Referer': 'http://www.chsi.com.cn/cet/'
  Then (cont) ->
    urllib.request cetGradeUrl, opts, cont
  .then (cont, cetHtml, urllibRes) ->
    unless urllibRes.statusCode is 200
      return res.reply '请稍候再试'

    if /无法找到对应的分数/.test(cetHtml)
      return res.reply '未找到相关成绩，请检查你回复的准考证号和姓名并重试'

    cetHtml = cetHtml.replace(/\n/g, '').replace(/\r/g, '').replace(/\t/g, '')
    grade =
      schoolName: /学校：<\/th><td>(.*?)<\/td>/.exec(cetHtml)[1]
      name: /姓名：<\/th><td>(.*?)<\/td>/.exec(cetHtml)[1]
      type: /考试类别：<\/th><td>(.*?)<\/td>/.exec(cetHtml)[1]
      cetNumber: /准考证号：<\/th><td>(.*?)<\/td>/.exec(cetHtml)[1]
      examDate: /考试时间：<\/th><td>(.*?)<\/td>/.exec(cetHtml)[1]
      totle: /<span class=\"colorRed\">(.*?)<\/span>/.exec(cetHtml)[1].trim()
      listening: /听力：<\/span>(.*?)<br \/>/.exec(cetHtml)[1].trim()
      read: /阅读：<\/span>(.*?)<br \/>/.exec(cetHtml)[1].trim()
      write: /写作与翻译：<\/span>(.*?)<\/td>/.exec(cetHtml)[1].trim()

    result = [new ImageText("                #{grade.type}成绩")]
    gradeStr = """
                姓名：#{grade.name}
                学校：#{grade.schoolName}
                考试时间：#{grade.examDate}

                总分：#{grade.totle}
                听力：#{grade.listening}
                阅读：#{grade.read}
                写作和翻译：#{grade.write}
              """
    result.push(new ImageText(gradeStr))
    res.reply result

  .fail (cont, err) ->
    logger.trace err

getTermEndExamInfo = (stuid, openid) ->
  url = 'http://202.118.167.76/ksap/all.asp'
  getNeauExamInfo(stuid, '期末考试', url, openid)

getMakeUpExamInfo = (stuid, openid) ->
  url = 'http://202.118.167.91/bm/ksap1/all.asp'
  getNeauExamInfo(stuid, '补考查询', url, openid)

getNeauExamInfo = (stuid, title, url, openid) ->
  Then (cont) ->
    opts =
      method: 'POST'
      data:
        keyword: stuid

    urllib.request url, opts, cont

  .then (cont, html, urllibRes) ->
    unless urllibRes.statusCode is 200
      wechatApi.sendText openid, "学校服务器累坏了，请稍候再试", wechatApiCallback
      return

    html = iconv.decode(html, 'GBK')
    msgs    = []
    $       = cheerio.load(html)
    items     = $('font tr')
    items.each (index, elem) ->
      children = $(this).find('font')
      msg       = {}
      msg.location  = children.eq(1).text().trim()
      msg.kch     = children.eq(2).text().trim()
      msg.courseName  = children.eq(3).text().trim()
      msg.stuid     = children.eq(4).text().trim()
      msg.stuName   = children.eq(5).text().trim()
      time      = children.eq(0).text().trim()
      if time.indexOf('请关注') isnt -1
        msg.time = '未安排'
        msg.location = '未安排'
      else if time.indexOf(msg.stuid) isnt -1
        msg.time = time[0..18]
      else
        msg.time = time
      msgs.push msg

    if msgs.length is 0
      wechatApi.sendText openid, "未查询到考试信息", wechatApiCallback

    else if msgs.length > 8
      examInfo = []
      nameAndStuidStr = '姓名:' + msgs[0].stuName + '\n' + '学号:' + msgs[0].stuid + '\n'
      examInfo.push('姓名:' + msgs[0].stuName + '\n')
      examInfo.push('学号:' + msgs[0].stuid + '\n')
      examInfo.push('------------------\n')
      for msg in msgs
        examInfo.push("科目名:#{msg.courseName}\n")
        examInfo.push("时间:#{msg.time}\n")
        examInfo.push("地点:#{msg.location}\n")
        examInfo.push("------------------\n")
      wechatApi.sendText openid, examInfo.join(''), wechatApiCallback
    else
      result = []
      result.push(new ImageText("                #{title}"))
      nameAndStuidStr = '  姓名:' + msgs[0].stuName + '\n' + '  学号:' + msgs[0].stuid
      result.push(new ImageText(nameAndStuidStr))
      for msg in msgs
        examStr = """
          #{msg.courseName}
          时间:#{msg.time}
          地点:  #{msg.location}
          """
        result.push(new ImageText(examStr))

      wechatApi.sendNews openid, result, wechatApiCallback

  .fail (cont, err) ->
    wechatApi.sendText openid, "学校服务器累坏了，请稍候再试", wechatApiCallback
